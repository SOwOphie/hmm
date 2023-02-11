{ lib, stdenv, lua5_4, makeWrapper, p7zip, libxml2, wget, curl, rsync, which }:

stdenv.mkDerivation rec {
 
  pname = "hmm";
  version = "0.0.1";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
    p7zip
    libxml2
    wget
    curl
    rsync
  ];

  buildInputs = [ lua5_4 ];


  isExecutable = true;

  # dontBuild = true;

  buildPhase = ''
    sed -i '1 s/lua5.4/lua/' hmm.lua
  '';

  installPhase = ''
    mkdir -p "$out/share/lua/hmm"
    cp -r host/ json_lua/ util.lua json.lua "$out/share/lua/hmm" 

    mkdir "$out/bin"
    cp hmm.lua "$out/bin/hmm.lua"
  '';

  postFixup = ''
    wrapProgram $out/bin/hmm.lua \
      --set LUA_PATH ";;$out/share/lua/?.lua;$out/share/lua/?/init.lua"
  '';

}


