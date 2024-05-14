#!/usr/bin/env bash

printf "μpkg was used but test had 'no-upkg' tag, do not tag tests that access upkg with 'no-upkg' ('# bats test_tags=no-upkg' or '# bats file_tags=no-upkg' at the top of the file)"
exit 127
