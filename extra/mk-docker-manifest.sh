#/usr/bin/bash

# Pack a file into a container image

INPUT=$1
INPUT_HASH=$(nix hash file --base16 $INPUT)
INPUT_SIZE=$(stat -c%s $INPUT)
INPUT_TYPE=$(file --mime-type $INPUT)

WORKDIR=$(mktemp -d)
cp -v $INPUT $WORKDIR/$INPUT_HASH

# this is the empty config
touch $WORKDIR/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

cat > $WORKDIR/manifest.json <<EOF
{
  "schemaVersion": 2,
  "config": {
    "mediaType": "application/nothing",
    "digest": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "size": 0
  },
  "layers": [
    {
      "mediaType": "$INPUT_TYPE",
      "digest": "sha256:$INPUT_HASH",
      "size": $INPUT_SIZE
    }
  ]
}
EOF

echo 'Directory Transport Version: 1.1' > $WORKDIR/version

echo "$WORKDIR"