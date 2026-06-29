# Pricing Router Device

Standalone HyperBEAM Forge package for `pricing-router@1.0`.

Route adapter for p4 pricing devices.

It lets a node keep a default pricing device while routing selected request templates to specialized pricing devices such as arweave-byte-pricing@1.0.

## Compatibility

- HyperBEAM pin: `4177b91993b2f590f4906bc9ca548724f8408875`
- Device name: `pricing-router@1.0`

## Build

```sh
rebar3 compile
rebar3 device package
rebar3 device verify
```

## Test

```sh
scripts/pre-push-test.sh
```

Install the local pre-push hook with:

```sh
scripts/install-git-hooks.sh
```

## Docs

- `docs/api.md`
- `docs/integration.md`
- `docs/generated.md`

Regenerate EDoc HTML with:

```sh
scripts/generate-docs.sh
```

## Publish

After tests pass, publish the Forge package artifacts generated under
`_build/device-packages/` with your normal ANS-104 item pipeline. Then pin the
published spec ID in your node's `name-resolvers` and trust the publisher
address in `trusted-device-signers`.
