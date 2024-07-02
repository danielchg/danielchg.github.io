---
title: "Tmux Cheatsheet"
date: 2024-07-02T11:16:02+02:00
tags: [Cheatsheet,Linux]
draft: false
---

# Table of Contents

- [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Cheat sheet](#cheat-sheet)
    - [Sessions](#sessions)
    - [Windows](#windows)
    - [Panes](#panes)
    - [Misc](#misc)

## Introduction

`tmux` is very useful when you have a remote session on a server via ssh, and you need to open multiple consoles, this avoid to open multiple ssh sessions to the server. Also it is very useful when you are working in pairs with a mate remotely, allowing both to share the same interactive session.

I have used `tmux` from time to time, and I always forget all the commands required to create new windows, panes, split current pane, rename window and so on. So here is a **cheatsheet** of the commands that I usually use on `tmux`. I will be updating this if I start to use new commands.

## Cheat sheet

### Sessions

* Create session

```bash
tmux
```

* List current sessions

```bash
❯ tmux ls
0: 1 windows (created Tue Jul  2 11:23:05 2024)
1: 1 windows (created Tue Jul  2 11:23:09 2024)
```

* Attach to session with id `0`

```bash
❯ tmux a -t 0
```

* Exit session without killing it

```bash
Ctrl+b d
```

* Exit session killing it

```bash
Ctrl+b x
```

### Windows

* Create a new window
```bash
Ctrl+b c
```

* Switch to window with id `2`

```bash
Ctrl+b 2
```

* Switch to next window on the right

```bash
Ctrl+b n
```

* Rename tab windows

```bash
Ctrl+b , <introduce the name of the tab>
```

### Panes

* Split current window horizontally 

```bash
Ctrl+b "
```

* Split current window vertically

```bash
Ctrl+b %
```

* Switch between panes

```bash
Ctrl+b <arrow key>
```

### Misc

* Enable mouse mode to allow scroll with the mouse wheel

```bash
Ctrl+b : set mouse on
```
