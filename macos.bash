#!/usr/bin/env bash

# This file provides support functionality for signing and notarising mac
# distributables.

# Codesigning (macOS)
# ===================
#
# macOS will reject executables that are not codesigned.  As such we need to
# sign them.  For this a Developer ID and signing certificate is required.  This
# can be obtained even with a free developer account at 
# https://developer.apple.com/account/resources/certificates/list
# It will also require the `codesign` executable.  If signing fails, you may
# need to install the 
#
#  > Apple Worldwide Developer Relations Certification Authority
#
# intermediate certificate, which can be downloaded from apples developer
# portal.
#
# For codesigning (executables and libraries), we can use
#
#  > security find-identity -v -p codesigning
#
# to find available code signing identities.  And then use 
#
#  > codesign --force \
#             --options runtime \
#             --timestamp \
#             --sign "Developer ID Application: John Doe (XXXXXXXXXX)" \
#             FILE
#

# Packaging (macOS)
# =================
# There are multiple ways to package software for macOS.  The simplest is a zip
# archive using `ditto`, we then also have installable `pkg`s, and mountable
# `dmg` disk images.
#
# Zip archive
# -----------
# After sigining the executables, we use `ditto` to create the relevant .zip
# file.
# 
#  > ditto -c -k --sequesterRsrc --zlibCompressionLevel 9 x y z pkg.zip
#

# Notarisation (macOS)
# ====================
#
# While a codesigned binary contains some trust that it originated with us, we
# need to have apple notarise it, so that gatekeeper will just happily accept
# it.  To do this, we could use notarytool form xcode, or the REST API that
# apple provides.  We'll opt for the REST API, as that doesn't require us to
# download and install xcode.
#
# For this we need to have an appstoreconnect credentials.  These can be
# obtained again from apple at https://appstoreconnect.apple.com/access/api.
# 
# We require curl, awscli, jq and and jwt-cli
#
# There will be a Key Identifier on the access/api page, in the form of
# 2X9R4HXF34, and a one-time option to download the associated
# AuthKey_2X9R4HXF34.p8 assoicated key with it. We'll also need the
# ISSuer ID, which looks like 57246542-96fe-1a63-e053-0824d011072a.
#
# With his we can then create the Json Web Token (JWT) as follows:
#
# > jwt encode --alg ES256 \
#              --aud appstoreconnect-v1 \
#              --kid 2X9R4HXF34 \
#              --exp $(date -d "now + 300 seconds" +%s) \
#              --payload 'scope=["POST /notary/v2/submissions", "GET /notary/v2/submissions"]' \
#              --payload iss=0d0b2b08-352f-410b-b9b4-af0b1c6592a8 \
#              --secret @<(cat AuthKey_2X9R4HXF34.p8 | grep -v "PRIVATE KEY" | base64 -d)
#
# Using curl, we can check for past submissing:
#
#  > curl -v -H "Authorization: Bearer <token>" "https://appstoreconnect.apple.com/notary/v2/submissions"
#
# To create a new one, we need the sha256 and name for what ever we want to
# notarise.  E.g. the .zip file we created with `ditto` above.
#
#  > read -r SHA NAME < <(sha256sum pkg.zip)
#
# With the JWT token written to e.g. $JWT, we can then
#
#  >  curl -H "Authorization: Bearer $JWT" \
#          -H 'Content-Type: application/json' \
#          -X POST https://appstoreconnect.apple.com/notary/v2/submissions \
#          -d '{"sha256":"$SHA", "submissionName": "$NAME"}'
#
# This will return some JSON of the form
#
#  { "data":
#    { "type": "newSubmissions"
#    , "id": "15041285-....-....-....-............"
#    , "attributes":
#      { "awsAccessKeyId": "..."
#      , "awsSecretAccessKey": "..."
#      , "awsSessionToken": "..."
#      , "bucket": "notary-submissions-prod"
#      , "object": "prod/..."} }
#  , "meta": {}}
#
# Which we can then use with `awscli` as follows:
#
#  > AWS_ACCESS_KEY_ID="$awsAccessKeyId" \
#    AWS_SECRET_ACCESS_KEY="$awsSecretAccessKey" \
#    AWS_SESSION_TOKEN="$awsSessionToken" \
#    aws s3 cp pkg.zip s3://$bucket/$object
#
# Once this is done, we can perodically poll the newSubmissions endpoint to see
# if notarisation has succeeded.
#