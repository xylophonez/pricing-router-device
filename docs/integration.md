# Integration

Use this as the p4 `pricing-device` when different routes need different
pricing logic.

Example:

```erlang
#{
    <<"device">> => <<"p4@1.0">>,
    <<"pricing-device">> => <<"pricing-router@1.0">>,
    <<"default-pricing-device">> => <<"simple-pay@1.0">>,
    <<"pricing-routes">> => [
        #{
            <<"template">> => <<"/~bundler@1.0/item">>,
            <<"pricing-device">> => <<"arweave-byte-pricing@1.0">>
        }
    ]
}
```

To make some signers free on a route while everyone else keeps paying, put an
allow-list device in front of the priced route and let it fall through. With the
node option `faff-allow-list` set to those addresses:

```erlang
<<"pricing-routes">> => [
    #{
        <<"template">> => <<"/~bundler@1.0/tx">>,
        <<"pricing-device">> => <<"faff@1.0">>,
        <<"fallthrough">> => true
    },
    #{
        <<"template">> => <<"/~bundler@1.0/tx">>,
        <<"pricing-device">> => <<"arweave-byte-pricing@1.11">>
    }
]
```

`faff@1.0` prices allow-listed signers at 0, so p4 serves them without touching
the ledger. It answers `infinity` for everyone else, who then fall through to
`arweave-byte-pricing@1.11`.
