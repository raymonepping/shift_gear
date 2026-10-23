# Five-minute proof identity; no KV, app-data key, key export, role edit or mount access.
path "shift-gear/transit/encrypt/sg-component-proof" { capabilities = ["update"] }
path "shift-gear/transit/decrypt/sg-component-proof" { capabilities = ["update"] }
path "shift-gear/transit/rewrap/sg-component-proof" { capabilities = ["update"] }
path "shift-gear/transit/keys/sg-component-proof/rotate" { capabilities = ["update"] }
path "shift-gear/pki-int/issue/sg-component-proof" { capabilities = ["update"] }
# Proof of possession limits revocation to a certificate whose key the caller has.
path "shift-gear/pki-int/revoke-with-key" { capabilities = ["update"] }
path "auth/token/revoke-self" { capabilities = ["update"] }
