"""python -m secure_door — DOOR_ROLE selects the party: verifier | client."""
import os
import sys

role = os.environ.get("DOOR_ROLE", "")
if role == "verifier":
    from .verifier import main
elif role == "client":
    from .client import main
else:
    sys.exit("DOOR_ROLE must be 'verifier' or 'client'")
main()
