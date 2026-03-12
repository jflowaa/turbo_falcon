#!/bin/bash

rm /tmp/turbo_falcon.tar.gz
tar --exclude-from='deployment/exclude.txt' --no-xattrs -czvf /tmp/turbo_falcon.tar.gz . && \
scp /tmp/turbo_falcon.tar.gz root@digital-ocean:/tmp && \
ssh digital-ocean << EOF
rm -rf ~/sites/turbo_falcon/
mkdir -p ~/sites/turbo_falcon/
tar -xzvf /tmp/turbo_falcon.tar.gz -C ~/sites/turbo_falcon && \
rm /tmp/turbo_falcon.tar.gz && \
cd ~/sites/turbo_falcon/ && \
asdf local elixir 1.18.4 && \
asdf local erlang 26.2.5.3 && \
MIX_ENV=prod mix deps.get --only prod && \
if [ -n "\$TURBO_FALCON_DATABASE_PATH" ]; then \
	DB_PARENT=\$(dirname "\$TURBO_FALCON_DATABASE_PATH") && \
	mkdir -p "\$DB_PARENT" && \
	if [ ! -f "\$TURBO_FALCON_DATABASE_PATH" ]; then \
		MIX_ENV=prod mix ecto.create || exit 1; \
	fi; \
else \
	MIX_ENV=prod mix ecto.create || exit 1; \
fi && \
MIX_ENV=prod mix ecto.migrate && \
MIX_ENV=prod mix assets.deploy && \
MIX_ENV=prod mix phx.gen.release && \
MIX_ENV=prod mix release && \
PHX_SERVER=true ~/sites/turbo_falcon/_build/prod/rel/turbo_falcon/bin/turbo_falcon daemon && \
PHX_SERVER=true ~/sites/turbo_falcon/_build/prod/rel/turbo_falcon/bin/turbo_falcon restart
EOF