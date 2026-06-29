# API

## `estimate/3`

Selects a route for the wrapped p4 request and forwards an estimate call to the
route-specific pricing device.

## `price/3`

Selects a route for the wrapped p4 request and forwards a price call to the
route-specific pricing device.

Configuration keys:

- `default-pricing-device`: defaults to `simple-pay@1.0`.
- `pricing-routes`: list/map of route entries. Each entry may include:
  - `template`: path template matched with `hb_util:template_matches/3`.
  - `pricing-device`: device used for matching requests.
  - any additional config copied into the forwarded pricing message.
