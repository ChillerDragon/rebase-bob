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

