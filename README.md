# pwstash
passwd stash for *nix


Example usage:

Run normally -

sudo ./pwstash.sh backup <user>
sudo ./pwstash.sh restore <user>


Do the seedbox password change (backs up first, then runs your command):

sudo ./pwstash.sh --seedbox-pass --user <user>
# or just:
sudo ./pwstash.sh --seedbox-pass


Only when you’re ready, explicitly restore the old password:

sudo ./pwstash.sh --restore-seedbox-pass --user <user>
# or:
sudo ./pwstash.sh --restore-seedbox-pass


