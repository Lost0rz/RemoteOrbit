# RemoteOrbitAudio HAL Driver

This component builds the independent `RemoteOrbitAudio` HAL driver used by
RemoteOrbit.

The build script:

1. downloads the pinned BlackHole `v0.7.1` source;
2. builds a distinct bundle ID, factory UUID, device UID, model UID,
   box name, and display name;
3. leaves the driver's outer Box transport as `virt`, but changes the actual
   audio Device transport to `usb ` in both Intel and Apple Silicon slices;
4. applies an ad-hoc local signature.

It does not modify the installed BlackHole driver. The generated bundle is:

`build/RemoteOrbitAudio.driver`

The source build is pinned because Doubao filters virtual audio devices on
this setup. The generated driver is installed side-by-side as
`RemoteOrbit Mic 2ch` and does not modify the original BlackHole driver.

`install-driver-safe.sh` installs only the new side-by-side bundle and refuses
to overwrite an existing copy. `install-driver.sh` backs up an existing
`RemoteOrbitAudio.driver` before installing the source-built bundle, while
`uninstall-driver.sh` removes only this project's driver. All three install
operations require administrator privileges.
