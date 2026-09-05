# The launchd agent

`lockstep --watch` runs until something kills it. This is the thing that starts
it at login and restarts it if it dies.

It is also where the device allowlist lives. There is no config file — the
`ProgramArguments` array below *is* the configuration, which is
[decision 0009](../../docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md)
and the reason changing the allowlist means reloading the agent.

## Grant Automation first, from a terminal

**Do this before loading the agent.** The first time `lockstep --watch` asks
Music a question, macOS shows an Automation permission prompt. A background
launchd agent may have no way to show that prompt, and a denied-by-default
permission looks exactly like Music being closed: every log line reads
`skip   Music is not running` while Music is plainly running.

With Music playing:

```
swiftc -O reference/lockstep.swift -o ~/bin/lockstep
~/bin/lockstep --watch --devices "$(~/bin/lockstep | sed -n 's/^device: *//p')"
```

Accept the prompt. Wait for one `set` or `noop` line, then Ctrl-C.

## Install

```
mkdir -p ~/bin ~/Library/LaunchAgents
swiftc -O reference/lockstep.swift -o ~/bin/lockstep

sed "s|YOUR-USERNAME|$(id -un)|g" \
  reference/launchd/me.ryanlindsey.lockstep.plist \
  > ~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist

# Edit the device name before loading — see below.
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist
```

Two edits are needed, and the `sed` above only makes one of them.

**`YOUR-USERNAME`** appears in three paths — the binary and both log paths. The
`sed` replaces all three. Do not shorten them to `~`: launchd does not expand
`~` or `$HOME`, and a job with a `~` in it respawns every ten seconds and never
runs.

**The device name** is still the author's DAC. Replace it with yours. It must
match what `lockstep` itself prints — including capitalisation and any trailing
digits. Surrounding whitespace is ignored on both sides, which matters more than
it sounds like it should: the author's DAC reports its own name with a trailing
space ([decision 0012](../../docs/decisions/0012-device-names-are-matched-trimmed.md)).
Nothing else is ignored — a partial name does not match.

```
lockstep | sed -n 's/^device: *//p'
```

For more than one device, comma-separate them inside the single `<string>`:
`<string>My DAC,My Other DAC</string>`.

## Verify

```
launchctl print "gui/$(id -u)/me.ryanlindsey.lockstep" | head -20
```

Expect `state = running` and a PID.

Then watch it work. With Music playing, skip a track:

```
tail -f ~/Library/Logs/lockstep.log
```

Expect an `event` line, and within about a second a `set`, `noop` or `skip`.

To see it actually change something rather than report a `noop`, put the device
deliberately out of step first and then skip a track:

```
lockstep 96000        # while a 44.1 kHz track is playing
# skip a track in Music
2026-09-05T06:45:11Z  event  playerInfo
2026-09-05T06:45:11Z  set    44100 Hz — verified
```

**Surviving logout and login cannot be checked any other way than by doing it.**
`launchctl kickstart -k` and a `bootout`/`bootstrap` cycle both restart the job
without ending the login session, which is the thing being tested. Note the PID,
log out, log back in, and compare:

```
launchctl print "gui/$(id -u)/me.ryanlindsey.lockstep" | awk '/pid = /{print $3}'
```

A different PID is a pass. The same PID means the session did not really end. No
job at all means `RunAtLoad` or the bootstrap did not persist.

## Change the allowlist

Edit the plist, then reload. Editing alone does nothing — launchd holds the
loaded copy.

```
launchctl bootout "gui/$(id -u)/me.ryanlindsey.lockstep"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist
```

## Uninstall

```
launchctl bootout "gui/$(id -u)/me.ryanlindsey.lockstep"
rm ~/Library/LaunchAgents/me.ryanlindsey.lockstep.plist
```

`bootout` exits 0 and prints nothing. Confirming it worked looks like a failure
and is not:

```
$ launchctl print "gui/$(id -u)/me.ryanlindsey.lockstep"
Bad request.
Could not find service "me.ryanlindsey.lockstep" in domain for user gui: 501
```

That is `print` reporting a service that no longer exists, which is the answer
you wanted.

This leaves `~/bin/lockstep` and the phase 1 Shortcuts working. Removing phase 2
does not undo phase 1 — the manual switch is still there, and is still the
override for anything Music is not playing.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Nothing in the log at all | The agent is not loaded | `launchctl print "gui/$(id -u)/me.ryanlindsey.lockstep"`; if it reports no such service, bootstrap it again and read the error |
| Nothing in the log, but `launchctl` says running | Stdout is not line-buffered — a modified build dropped the `setvbuf` call | Restore it. A block-buffered stream holds hours of events before any reach the file |
| Every line reads `skip   Music is not running` | Automation permission denied or never asked | System Settings → Privacy & Security → Automation, and check `lockstep` against Music. Grant it from a terminal as above, then `launchctl kickstart -k "gui/$(id -u)/me.ryanlindsey.lockstep"` |
| The two startup banner lines repeat every ten seconds | The binary is exiting immediately and `KeepAlive` is restarting it — wrong path, or `--devices` missing or empty | Check the binary path in the plist, and that the device name is non-empty. Ten seconds is launchd's respawn throttle doing its job |
| `error  device reports N Hz after the change` | The DAC accepted the call and did not apply the rate | This is the phase 1 read-back rule catching a real failure, not a bug in the agent. The device does not hold that rate; check what it actually reported in phase 0 |
| `skip   <device> is not in the allowlist` for a device you meant to allow | The name does not match | `lockstep \| sed -n 's/^device: *//p'` and paste that string in. Leading and trailing spaces are ignored; nothing else is |

## Why `bootstrap` and not `load`

`launchctl load` and `unload` are the deprecated spellings. They still work and
they report failures worse — often silently. Use `bootstrap` and `bootout`.
