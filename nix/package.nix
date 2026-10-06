{ lib
, stdenv
, cargo
, rustc
, naersk
, patchelf
, pkg-config

# Runtime dlopen dependencies for the panel binary (eframe/egui).
# These are NOT recorded as ELF NEEDED entries, so ldd auto-patching
# misses them.  We add their lib paths to RPATH manually.
, libX11
, libXrandr
, libXcursor
, libXi
, libxkbcommon
, mesa
, libglvnd
}:

let
  runtimeLibs = [
    libX11 libXrandr libXcursor libXi libxkbcommon mesa libglvnd
  ];
  runtimeLibPaths = lib.makeLibraryPath runtimeLibs;

  # A naersk builder that builds the whole workspace.
  # naersk handles fetching all crate dependencies, then we override the
  # build and install phases to build the entire workspace at once.
  nightlightd = naersk.buildPackage {
    root = ./..;                       # workspace root
    cargoLock = ./../Cargo.lock;       # locked deps

    # Packages available at build time (native = in PATH).
    nativeBuildInputs = [ pkg-config ];

    # Packages available in the build environment (for cargo's pkg-config
    # probes that eframe/egui runs during the build).
    buildInputs = runtimeLibs ++ [ patchelf ];

    # Build the entire workspace, not just the member naersk resolves to.
    buildPhase = ''
      cargo build \
        --release \
        --workspace \
        --frozen \
        --target-dir target
    '';

    installPhase = ''
      # ── Binaries ────────────────────────────────────────────────
      install -Dm755 target/release/nightlightd      $out/bin/nightlightd
      install -Dm755 target/release/nightlight-tray  $out/bin/nightlight-tray
      install -Dm755 target/release/nightlight-panel $out/bin/nightlight-panel
      install -Dm755 target/release/nightlight-tui   $out/bin/nightlight-tui

      # ── Systemd user service ────────────────────────────────────
      # Use the packaged variant (ExecStart = /usr/bin/...) so the
      # substituteInPlace below rewrites it to the Nix store path.
      install -Dm644 dist/deb/nightlightd.service \
        $out/lib/systemd/user/nightlightd.service
      substituteInPlace $out/lib/systemd/user/nightlightd.service \
        --replace /usr/bin/nightlightd $out/bin/nightlightd

      # ── Tray autostart entry ────────────────────────────────────
      install -Dm644 dist/nightlight-tray.desktop \
        $out/etc/xdg/autostart/nightlight-tray.desktop
      substituteInPlace $out/etc/xdg/autostart/nightlight-tray.desktop \
        --replace "Exec=nightlight-tray" "Exec=$out/bin/nightlight-tray"

      # ── Panel applications-menu entry ───────────────────────────
      install -Dm644 dist/nightlight-panel.desktop \
        $out/share/applications/nightlight-panel.desktop
      substituteInPlace $out/share/applications/nightlight-panel.desktop \
        --replace "Exec=nightlight-panel" "Exec=$out/bin/nightlight-panel"

      # ── Documentation ───────────────────────────────────────────
      install -Dm644 README.md $out/share/doc/nightlightd/README.md

      # ── RPATH for dlopen'd libs ─────────────────────────────────
      # The panel dlopen's GL, EGL, X11, xkbcommon at runtime.  Since
      # these are not ELF NEEDED, the auto-patcher misses them.
      for bin in $out/bin/*; do
        patchelf --add-rpath "${runtimeLibPaths}" "$bin"
      done
    '';

    # Let the compiler/strip step run.
    # The default is already to strip release builds.
  };
in
nightlightd