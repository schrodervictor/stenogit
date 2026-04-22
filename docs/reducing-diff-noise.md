# Reducing diff noise with git clean filters

Some tracked files are rewritten by their owning process in ways that
produce large diffs with no semantic meaning. The canonical example is
a JSON config file whose writer does not sort keys: every save
reshuffles the object and stenogit commits hundreds of reordering
lines around a single real change.

Git has a built-in mechanism for this: a **clean filter** transforms
content on its way from the working tree into the index, so commits
and diffs only reflect canonical form. The working tree is never
touched, so the writing process is unaffected.

## Example: sort JSON keys

Configure the filter in the tracked directory's local git config:

```sh
git config filter.json-sort.clean 'jq --sort-keys .'
```

Then create a `.gitattributes` file in the tracked directory:

```
config.json filter=json-sort
```

From the next stenogit trigger onwards, `config.json` is sorted before
staging. The file on disk keeps whatever order the writing process
produced.

## Applying to existing history

The filter only affects new commits. If the repo already has noisy
history, run once to normalize the index:

```sh
git add --renormalize .
git commit -m 'normalize: apply json-sort filter'
```

This produces one new commit with a large "normalization" diff. All
subsequent commits are clean. Past commits stay untouched.

## Best-effort vs strict

By default, if the filter command fails (jq missing, malformed JSON
from a torn read, etc.), git falls back to storing the raw content
and the commit still succeeds. This is usually what you want with
stenogit, which retries on the next trigger.

To make filter failures abort the commit instead:

```sh
git config filter.json-sort.required true
```

## Persistence caveat

Filter definitions live in `.git/config`, which is not tracked by git.
If `.git/` is wiped, the repo is cloned elsewhere, or you apply the
filter to a pre-existing repo, the `git config` command has to be
re-run. Document the setup commands in the tracked directory (for
example, as comments at the top of its `.gitattributes`) so they are
not lost.

## Other canonicalizers

The same pattern works for any format with a canonical form:

| File type | Clean filter command |
|-----------|----------------------|
| JSON | `jq --sort-keys .` |
| YAML | `yq --sort-keys .` (yq 4+) |
| TOML | no standard canonicalizer; write a small script if needed |
| XML | `xmllint --c14n -` |
| Binary / mixed | skip; clean filters operate on text |

For JSON where array order is also meaningless, recursively sort
arrays too:

```sh
git config filter.json-sort-deep.clean \
    'jq "walk(if type == \"array\" then sort else . end)"'
```

This is heavier-handed; use only when array order truly carries no
meaning.
