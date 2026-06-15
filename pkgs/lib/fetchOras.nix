{ stdenv, oras, cacert }:
{
  reference,
  sha256,
  name ? "fetchOras-${baseNameOf reference}",
}:
stdenv.mkDerivation {
  inherit name;
  outputHash = sha256;
  outputHashMode = "flat";
  outputHashAlgo = "sha256";
  nativeBuildInputs = [
    oras
    cacert
  ];
  buildCommand = ''
    export HOME=$(mktemp -d)
    mkdir -p tmp
    oras pull ${reference} -o tmp
    # Chunks were pushed as part-0, part-1, ...; alphabetic glob order is concat order.
    cat tmp/part-* > $out
  '';
  meta = {
    description = "Fetch a chunked OCI artifact from a registry";
  };
}
