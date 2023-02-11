{
  description = "";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
  (flake-utils.lib.simpleFlake {
    inherit self nixpkgs;
    name = "hmm";
    overlay = _: prev: {
      hmm = {
        hmm = prev.callPackage ./hmm.nix {};
      };
    };
  });
}
