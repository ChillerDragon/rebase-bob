# rebase-bob
Hello I am bob the rebase bot

## dependencies

- POSIX shell
- jq
- github cli
- git

## setup

Install the github cli and then login:

```bash
mkdir -p gh
GH_CONFIG_DIR=./gh gh auth login
```

Copy the example config:

```bash
cp env.example .env
```
then open `.env` with your favorite text editor and adapt the values.


Then for all the configured remotes you need the local git repositories.
For example if your `.env` looks like this.

```sh
export ALLOWED_REMOTES="ddnet/ddnet teeworlds/teeworlds"
export GIT_ROOT=/home/chiller/git/rebase-bob/data
```

You need local git repositories with a origin (your fork) and upstream (upstream duh) remote like this.

```
chiller@host:~/git/rebase-bob$ tree data/ -L 2
data/
├── ddnet
│   └── ddnet
└── teeworlds
    └── teeworlds
```
