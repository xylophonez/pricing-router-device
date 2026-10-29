# API

## `estimate/3`

Selects a route for the wrapped p4 request and forwards an estimate call to the
route-specific pricing device.

## `price/3`

Selects a route for the wrapped p4 request and forwards a price call to the
route-specific pricing device.

Routes are tried in order. The first matching route decides the price, unless it
sets `fallthrough`: then an `infinity` answer from its device passes the request
to the next matching route, and finally to `default-pricing-device`. A
fall-through route whose device has no `price` key is asked for its `estimate`
instead, as p4 does.

Configuration keys:

- `default-pricing-device`: defaults to `simple-pay@1.0`.
- `pricing-routes`: list/map of route entries. Each entry may include:
  - `template`: path template matched with `hb_util:template_matches/3`.
  - `pricing-device`: device used for matching requests.
  - `fallthrough`: `true` (or `"true"`) to continue past an `infinity` answer.
    Defaults to `false`, which keeps first-match behaviour.
  - any additional config copied into the forwarded pricing message.
