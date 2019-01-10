{nixpkgs ? import <nixpkgs> {}}:

let
  inherit (nixpkgs) fetchurl callPackage;

  bionix = nixpkgs.lib.makeExtensible (self:
  let callBionix = file: attrs: import file ({ bionix = self; } // attrs);
  in with self; {
    callBionix = callBionix;
    id = x: x;
    exec = f: x: y: f x y;
    callBionixE = p: exec (callBionix p);

    types = callBionix ./lib/types.nix {};

    bowtie = callBionix ./tools/bowtie.nix {};
    bwa = callBionix ./tools/bwa.nix {};
    cnvkit = callBionix ./tools/cnvkit.nix {};
    compression = callBionix ./tools/compression.nix {};
    crumble = callBionix ./tools/crumble.nix {};
    fastqc = callBionix ./tools/fastqc.nix {};
    gridss = callBionix ./tools/gridss.nix {};
    infercnv = callBionix ./tools/infercnv.nix {};
    kallisto = callBionix ./tools/kallisto.nix {};
    mosdepth = callBionix ./tools/mosdepth.nix {};
    mutect = callBionix ./tools/mutect.nix {};
    platypus = callBionix ./tools/platypus.nix {};
    samtools = callBionix ./tools/samtools.nix {};
    snpeff = callBionix ./tools/snpeff.nix {};
    strelka = callBionix ./tools/strelka.nix {};
    ref = callBionix ./lib/references.nix {};

    qsub = attrs: bionix.extend (self: super: with self; rec {
      qsubDefs = { ppn = 1; mem = 1; walltime = "24:00:00"; tmpDir = "/tmp"; sleepTime = 60; } // attrs;
      qsub = attrs: (callPackage ./lib/qsub.nix {}) (qsubDefs // attrs);
      exec = f: x: y: qsub (builtins.intersectAttrs qsubDefs x) (f (builtins.removeAttrs x (builtins.attrNames qsubDefs)) y);
    });
    def = f: defs: attrs: f (defs // attrs);
    pipe = let g = fs: with builtins; let h = head fs; t = tail fs; in if t != [] then x: (g t (h x)) else h; in g;

    link = {src, dst}: ''
      d=$(dirname ${dst})
      if [ ! -e $out/$d ] ; then
        mkdir -p $out/$d
      fi
      ln -s ${src} $out/${dst}
    '';
    mkLinks = nixpkgs.lib.concatMapStringsSep "\n" link;
    linkDrv = x: nixpkgs.stdenvNoCC.mkDerivation {
      name = "link";
      buildCommand = mkLinks x;
    };
    ln = x: y: { src = x; dst = y; };

    # Fetching files of specific type
    fetchFastQ = attrs: with types; tagFiletype (filetype.fq {}) (fetchurl attrs);
    fetchFastA = attrs: with types; tagFiletype (filetype.fa {}) (fetchurl attrs);
    fetchFastQGZ = attrs: with types; tagFiletype (filetype.gz (filetype.fq {})) (fetchurl attrs);
    fetchFastAGZ = attrs: with types; tagFiletype (filetype.gz (filetype.fa {})) (fetchurl attrs);

    # Export nixpkgs and standard library lib
    pkgs = nixpkgs;
    lib = nixpkgs.lib // { types = types; };
    stage = nixpkgs.stdenv.mkDerivation;

    # splitting/joining
    splitFile = file: drv: stage {
      name = "split-${file}";
      buildCommand = "ln -s ${drv}/${file} $out";
    };
    split = drv: lib.mapAttrs (p: _: splitFile p drv) (builtins.readDir drv);
    join = drvs: stage {
      name = "join";
      buildCommand = ''
        mkdir $out
        ${builtins.concatStringsSep "\n" (builtins.attrValues (lib.mapAttrs (n: d: "ln -s ${d} $out/${n}") drvs))}
      '';
    };
    each = f: drv: join (lib.mapAttrs (_: f) (split drv));
  });
in bionix
