{ lib, stdenv, fetchFromGitHub, fetchurl, makeWrapper, makeDesktopItem, linkFarmFromDrvs
, dotnet-sdk_5, dotnetPackages, dotnetCorePackages, cacert
, SDL2, libX11, libgdiplus, ffmpeg, openal, libsoundio
, gtk3, gobject-introspection, gdk-pixbuf, wrapGAppsHook
}:

let
  runtimeDeps = [
    SDL2
    gtk3
    libX11
    libgdiplus
    ffmpeg
    openal
    libsoundio
  ];
in stdenv.mkDerivation rec {
  pname = "ryujinx";
  version = "1.0.6864"; # Versioning is based off of the official appveyor builds: https://ci.appveyor.com/project/gdkchan/ryujinx

  src = fetchFromGitHub {
    owner = "Ryujinx";
    repo = "Ryujinx";
    rev = "b94dc01d4357c608d60383e85f709312294fd833";
    sha256 = "02g3zijnpb9v3dwnfhkz6smz7643rpy270kipgs9hjlmdg7dz54c";
  };

  nativeBuildInputs = [ dotnet-sdk_5 dotnetPackages.Nuget cacert makeWrapper wrapGAppsHook gobject-introspection gdk-pixbuf ];

  nugetDeps = linkFarmFromDrvs "${pname}-nuget-deps" (import ./deps.nix {
    fetchNuGet = { name, version, sha256 }: fetchurl {
      name = "nuget-${name}-${version}.nupkg";
      url = "https://www.nuget.org/api/v2/package/${name}/${version}";
      inherit sha256;
    };
  });

  # Change hardcoded search path for ffmpeg from "/lib" to a path to the nix store
  prePatch = ''
    substituteInPlace Ryujinx/Program.cs --replace \
      "ffmpeg.RootPath = \"/lib\"\;" "ffmpeg.RootPath = \"${ffmpeg}/lib\"\;"
  '';

  patches = [
    ./log.patch # Without this, Ryujinx attempts to write logs to the nix store. This patch makes it write to "~/.config/Ryujinx/Logs" on Linux.
  ];

  configurePhase = ''
    runHook preConfigure

    export HOME=$(mktemp -d)
    export DOTNET_CLI_TELEMETRY_OPTOUT=1
    export DOTNET_NOLOGO=1

    nuget sources Add -Name nixos -Source "$PWD/nixos"
    nuget init "$nugetDeps" "$PWD/nixos"

    # FIXME: https://github.com/NuGet/Home/issues/4413
    mkdir -p $HOME/.nuget/NuGet
    cp $HOME/.config/NuGet/NuGet.Config $HOME/.nuget/NuGet

    dotnet restore --source "$PWD/nixos" Ryujinx.sln

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    dotnet build Ryujinx.sln \
      --no-restore \
      --configuration Release \
      -p:Version=${version}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    dotnet publish Ryujinx.sln \
      --no-build \
      --configuration Release \
      --no-self-contained \
      --output $out/lib/ryujinx
    shopt -s extglob

    makeWrapper $out/lib/ryujinx/Ryujinx $out/bin/Ryujinx \
      --set DOTNET_ROOT "${dotnetCorePackages.net_5_0}" \
      --suffix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeDeps}" \
      ''${gappsWrapperArgs[@]}

    for i in 16 32 48 64 96 128 256 512 1024; do
      install -D ${src}/Ryujinx/Ui/Resources/Logo_Ryujinx.png $out/share/icons/hicolor/''${i}x$i/apps/ryujinx.png
    done
    cp -r ${makeDesktopItem {
      desktopName = "Ryujinx";
      name = "ryujinx";
      exec = "Ryujinx";
      icon = "ryujinx";
      comment = meta.description;
      type = "Application";
      categories = "Game;";
    }}/share/applications $out/share

    runHook postInstall
  '';

  # Strip breaks the executable.
  dontStrip = true;

  meta = with lib; {
    description = "Experimental Nintendo Switch Emulator written in C#";
    homepage = "https://ryujinx.org/";
    license = licenses.mit;
    maintainers = [ maintainers.ivar ];
    platforms = [ "x86_64-linux" ];
  };
  passthru.updateScript = ./updater.sh;
}
