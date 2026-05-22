{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.5.20";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.5.20/OpenClaw-2026.5.20.zip";
    hash = "sha256-u0wvseg5KVKk7l0Nw7nbcNRjH5dV9qcjMxk+n/u+4Yo=";
    stripRoot = false;
  };

  dontUnpack = true;

  installPhase = "${../scripts/openclaw-app-install.sh}";

  meta = with lib; {
    description = "OpenClaw macOS app bundle";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
