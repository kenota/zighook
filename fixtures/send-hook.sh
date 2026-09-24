#!/bin/sh
#
curl \
  -vvv \
  -XPOST \
  -H "Host: binarybuffer.com:3333" \
  -H "User-Agent: GitHub-Hookshot/48b72cd" \
  -H "Accept: */*" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Delivery: c71bc6fa-b805-11f1-8dad-3c2b36bdc7e9" \
  -H "X-GitHub-Event: ping" \
  -H "X-GitHub-Hook-ID: 684838181" \
  -H "X-GitHub-Hook-Installation-Target-ID: 1379967204" \
  -H "X-GitHub-Hook-Installation-Target-Type: repository" \
  -H "X-Hub-Signature: sha1=1531f42d81e8dbb890cb95f17e23f47998df0bde" \
  -H "X-Hub-Signature-256: sha256=f2757aac40acb49663d7c0d0986fd7490602d4eecf46fc0c172820cdd0c997c3" \
  --data @payload.json \
  http://localhost:3333


