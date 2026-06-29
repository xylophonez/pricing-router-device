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
