# Third-party notices

`remote-orbit` contains code adapted from
[fanxeon/mi-ao](https://github.com/fanxeon/mi-ao), distributed under the MIT
License, Copyright (c) 2026 FanXeon@Poemcoder with Codex.

Its ATVV protocol and IMA/DVI ADPCM implementation were informed by:

- [b0o/ATVVoice](https://github.com/b0o/ATVVoice), MIT License,
  Copyright (c) 2026 Maddison Cohodas.
- [Google Voice over BLE specification v1.0](https://wangefan.github.io/linux_kernel_driver/resources/Google_Voice_over_BLE_spec_v1.0.pdf).

`RemoteOrbitAudio.driver` is a modified build of
[ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole)
0.7.1 and remains licensed under GNU GPL v3. The build script documents every
binary-level modification. BlackHole's original license is
preserved inside the generated driver bundle.

## Modifier shortcut virtual HID client

The source snapshot under
`remote-orbit/Sources/RemoteOrbitHIDBridge/vendor/upstream/` is from
`pqrs-org/Karabiner-DriverKit-VirtualHIDDevice` v8.6.0 at commit
`9036bc771259ff8d61341f4d1b7072b954fdb2fa`, and `remote-orbit/Packaging/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg`
is the upstream v8.6.0 release package distributed under The Unlicense (`vendor/upstream/LICENSE.md`).
Its upstream `LICENSE.md` is included in that snapshot and applies where a more
specific header notice does not apply. The 620-file include closure and each file's
Git blob ID and SHA-256 are recorded in `vendor/upstream/manifest.json`.

Specific vendored components retain their upstream terms:

- pqrs headers and standalone Asio 1.38.2 carry the Boost Software License 1.0
  notice; Asio carries Copyright (c) 2003-2026 Christopher M. Kohlhoff. See
  the full license text at
  `remote-orbit/Sources/RemoteOrbitHIDBridge/vendor/upstream/licenses/boost-LICENSE_1_0.txt`.
- Microsoft GSL headers carry the MIT license and the Microsoft copyright
  notice in each affected file.
- `nod/nod.hpp` is from `fr00b0/nod` commit
  `23e4190f3d15964dd1f00677120a788824d74ec9`; its MIT license is included at
  `vendor/upstream/licenses/nod-LICENSE`.
- `type_safe/strong_typedef.hpp` is from `foonathan/type_safe` commit
  `292e8c127037e33d92f8f52dab0f1184993942d0`; its MIT license is included at
  `vendor/upstream/licenses/type_safe-LICENSE`.
