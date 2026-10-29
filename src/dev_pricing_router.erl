%%% @doc Route requests to different P4 pricing devices.
%%%
%%% This is a small pricing-device adapter. It allows a node to keep static
%%% route prices on `simple-pay@1.0' while sending specific routes to another
%%% narrow pricing device.
%%%
%%% A route may set `fallthrough' to `true'. When that route's device answers
%%% `infinity' for a request, the router continues with the next matching
%%% route (or the default device) instead of refusing the request. This lets
%%% an allow-list device such as `faff@1.0' make some signers free while every
%%% other signer keeps the route's normal pricing.
-module(dev_pricing_router).
-implements(<<"pricing-router@1.1">>).
-export([info/1, estimate/3, price/3]).

-include_lib("hb/include/hb.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

info(_) ->
    #{ exports => [<<"estimate">>, <<"price">>] }.

estimate(Base, Req, Opts) ->
    forward(<<"estimate">>, Base, Req, Opts).

price(Base, Req, Opts) ->
    forward(<<"price">>, Base, Req, Opts).

forward(Path, Base, Req0, Opts) ->
    Req = Req0#{ <<"path">> => Path },
    forward_routes(Base, Req, matching_routes(Base, Req, Opts), Opts).

%% @doc Resolve the first matching route. A `fallthrough' route that answers
%% `infinity' hands the request to the next matching route, and finally to the
%% default device.
forward_routes(Base, Req, [], Opts) ->
    hb_ao:resolve(pricing_msg(Base, #{}, Opts), Req, Opts);
forward_routes(Base, Req, [Route | Rest], Opts) ->
    PricingMsg = pricing_msg(Base, Route, Opts),
    case fallthrough(Route, Opts) of
        false ->
            hb_ao:resolve(PricingMsg, Req, Opts);
        true ->
            case fallthrough_quote(PricingMsg, Req, Opts) of
                {ok, <<"infinity">>} -> forward_routes(Base, Req, Rest, Opts);
                Other -> Other
            end
    end.

%% @doc A device without `price' is asked for its `estimate', as p4 itself does
%% when a pricing device cannot price a response.
fallthrough_quote(PricingMsg, Req = #{ <<"path">> := <<"price">> }, Opts) ->
    case hb_ao:resolve(PricingMsg, Req, Opts) of
        {error, _} -> hb_ao:resolve(PricingMsg, Req#{ <<"path">> => <<"estimate">> }, Opts);
        Res -> Res
    end;
fallthrough_quote(PricingMsg, Req, Opts) ->
    hb_ao:resolve(PricingMsg, Req, Opts).

fallthrough(Route, Opts) ->
    case hb_maps:get(<<"fallthrough">>, Route, false, Opts) of
        true -> true;
        <<"true">> -> true;
        _ -> false
    end.

pricing_msg(Base, Route, Opts) ->
    Device =
        hb_maps:get(
            <<"pricing-device">>,
            Route,
            hb_maps:get(<<"default-pricing-device">>, Base, <<"simple-pay@1.0">>, Opts),
            Opts
        ),
    (maps:merge(Base, maps:without([<<"template">>, <<"fallthrough">>], Route)))#{
        <<"device">> => Device
    }.

matching_routes(Base, Req, Opts) ->
    Request = hb_ao:get(<<"request">>, Req, #{}, Opts#{ <<"hashpath">> => ignore }),
    Routes =
        hb_maps:get(
            <<"pricing-routes">>,
            Base,
            hb_opts:get(<<"pricing-routes">>, [], Opts),
            Opts
        ),
    route_matches(Request, Routes, Opts).

route_matches(Request, Routes, Opts) ->
    TargetPath =
        case hb_util:find_target_path(Request, Opts) of
            no_path -> no_path;
            {_TargetKey, Path} -> Path
        end,
    match_routes(Request#{<<"path">> => TargetPath}, list_routes(Routes, Opts), Opts).

list_routes(Routes, Opts) when is_map(Routes) ->
    case hb_util:is_ordered_list(Routes, Opts) of
        true -> hb_util:message_to_ordered_list(Routes, Opts);
        false -> hb_maps:values(Routes, Opts)
    end;
list_routes(Routes, _Opts) when is_list(Routes) ->
    Routes;
list_routes(_Routes, _Opts) ->
    [].

match_routes(Request, Routes, Opts) ->
    [
        Route
    ||
        Route <- Routes,
        hb_util:template_matches(
            Request,
            hb_maps:get(<<"template">>, Route, #{}, Opts),
            Opts
        )
    ].

%%% Tests

-ifdef(TEST).

%% Routes for a request whose path is `/priced'. The first route lets
%% allow-listed signers through for free; everyone else falls through to the
%% second route's `simple-pay@1.0' price.
faff_then_priced(Fallthrough) ->
    [
        #{
            <<"template">> => <<"^/priced">>,
            <<"pricing-device">> => <<"faff@1.0">>,
            <<"fallthrough">> => Fallthrough
        },
        #{
            <<"template">> => <<"^/priced">>,
            <<"pricing-device">> => <<"simple-pay@1.0">>
        }
    ].

router_base(Routes) ->
    #{
        <<"default-pricing-device">> => <<"simple-pay@1.0">>,
        <<"pricing-routes">> => Routes
    }.

pricing_req(Path, Wallet) ->
    Request = hb_message:commit(#{ <<"path">> => <<"/priced">> }, #{ <<"priv-wallet">> => Wallet }),
    #{ <<"path">> => Path, <<"request">> => Request, <<"body">> => [Request] }.

router_opts(Owner) ->
    #{
        <<"faff-allow-list">> => [hb_test_utils:committer(Owner)],
        <<"simple-pay-price">> => 5,
        <<"operator">> => hb_test_utils:committer(ar_wallet:new())
    }.

allow_listed_signer_is_free_test() ->
    Owner = ar_wallet:new(),
    Base = router_base(faff_then_priced(true)),
    Opts = router_opts(Owner),
    ?assertEqual({ok, 0}, estimate(Base, pricing_req(<<"estimate">>, Owner), Opts)),
    % faff has no `price'; the router asks for its estimate, as p4 does.
    ?assertEqual({ok, 0}, price(Base, pricing_req(<<"price">>, Owner), Opts)).

other_signers_fall_through_to_next_route_test() ->
    Owner = ar_wallet:new(),
    Stranger = ar_wallet:new(),
    Base = router_base(faff_then_priced(true)),
    Opts = router_opts(Owner),
    PricedOnly = router_base(tl(faff_then_priced(true))),
    {ok, Estimate} = estimate(Base, pricing_req(<<"estimate">>, Stranger), Opts),
    ?assert(is_integer(Estimate) andalso Estimate > 0),
    % The stranger gets exactly what the priced route alone returns. For
    % `simple-pay@1.0' that is `not_found' for `price', so p4 asks for an
    % estimate, as it did before routes could fall through.
    PriceReq = pricing_req(<<"price">>, Stranger),
    ?assertEqual(price(PricedOnly, PriceReq, Opts), price(Base, PriceReq, Opts)).

binary_true_enables_fallthrough_test() ->
    Owner = ar_wallet:new(),
    Base = router_base(faff_then_priced(<<"true">>)),
    {ok, Estimate} = estimate(Base, pricing_req(<<"estimate">>, ar_wallet:new()), router_opts(Owner)),
    ?assert(Estimate > 0).

without_fallthrough_first_match_still_decides_test() ->
    Owner = ar_wallet:new(),
    Base = router_base(faff_then_priced(false)),
    Opts = router_opts(Owner),
    ?assertEqual({ok, 0}, estimate(Base, pricing_req(<<"estimate">>, Owner), Opts)),
    ?assertEqual(
        {ok, <<"infinity">>},
        estimate(Base, pricing_req(<<"estimate">>, ar_wallet:new()), Opts)
    ).

exhausted_fallthrough_uses_default_device_test() ->
    Owner = ar_wallet:new(),
    Base = router_base([hd(faff_then_priced(true))]),
    {ok, Estimate} = estimate(Base, pricing_req(<<"estimate">>, ar_wallet:new()), router_opts(Owner)),
    ?assert(Estimate > 0).

no_route_uses_default_device_test() ->
    Owner = ar_wallet:new(),
    Base = router_base([]),
    {ok, Estimate} = estimate(Base, pricing_req(<<"estimate">>, Owner), router_opts(Owner)),
    ?assert(Estimate > 0).

%% A p4 node prices `/greeting' through the router: the allow-listed owner is
%% served with no balance and is never debited; another signer must pay.
p4_node_charges_only_non_allow_listed_signers_test_() ->
    {timeout, 60, fun p4_node_charges_only_non_allow_listed_signers/0}.
p4_node_charges_only_non_allow_listed_signers() ->
    Owner = ar_wallet:new(),
    Payer = ar_wallet:new(),
    Broke = ar_wallet:new(),
    OwnerAddress = hb_test_utils:committer(Owner),
    PayerAddress = hb_test_utils:committer(Payer),
    Router = #{ <<"estimate">> => fun estimate/3, <<"price">> => fun price/3 },
    Processor = #{
        <<"device">> => <<"p4@1.0">>,
        <<"pricing-device">> => Router,
        <<"ledger-device">> => <<"simple-pay@1.0">>,
        <<"default-pricing-device">> => <<"simple-pay@1.0">>,
        <<"pricing-routes">> => [
            #{
                <<"template">> => <<"greeting">>,
                <<"pricing-device">> => <<"faff@1.0">>,
                <<"fallthrough">> => true
            },
            #{
                <<"template">> => <<"greeting">>,
                <<"pricing-device">> => <<"simple-pay@1.0">>
            }
        ]
    },
    Node = hb_http_server:start_node(#{
        <<"faff-allow-list">> => [OwnerAddress],
        <<"simple-pay-price">> => 5,
        <<"simple-pay-ledger">> => #{ PayerAddress => 100 },
        <<"on">> => #{ <<"request">> => Processor, <<"response">> => Processor }
    }),
    Req = #{ <<"path">> => <<"//greeting">>, <<"greeting">> => <<"Hello, world!">> },
    Signed = fun(Wallet) -> hb_message:commit(Req, #{ <<"priv-wallet">> => Wallet }) end,
    Balance =
        fun(Wallet) ->
            hb_http:get(
                Node,
                hb_message:commit(
                    #{ <<"path">> => <<"/~p4@1.0/balance">> },
                    #{ <<"priv-wallet">> => Wallet }
                ),
                #{}
            )
        end,
    ?assertEqual({ok, <<"Hello, world!">>}, hb_http:get(Node, Signed(Owner), #{})),
    ?assertEqual({ok, <<"Hello, world!">>}, hb_http:get(Node, Signed(Owner), #{})),
    ?assertEqual({ok, 0}, Balance(Owner)),
    ?assertEqual({ok, <<"Hello, world!">>}, hb_http:get(Node, Signed(Payer), #{})),
    {ok, PayerBalance} = Balance(Payer),
    ?assert(PayerBalance < 100),
    ?assertMatch({error, _}, hb_http:get(Node, Signed(Broke), #{})).

-endif.
