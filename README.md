# CloudStatus

🇬🇧 English | [🇪🇸 Español](README.es.md)

> Interpreting Syncthing for humans.

<p align="center">

  <img src="images/general.png" alt="CloudStatus" width="800">

</p>

## What is CloudStatus?

CloudStatus is a macOS menu bar app that lets you check the status of your Syncthing synchronization at a glance.

Its goal is simple: turn technical information into meaningful information.

Instead of making you interpret connections, indexes, or cryptic status messages, CloudStatus answers the questions you actually care about:

- Is everything synced?
- Which device is currently syncing?
- Which files were just received?
- Do I need to do anything?

A quick glance at the cloud icon in your menu bar tells you whether everything is running smoothly. If you need more detail, CloudStatus provides a clean, intuitive interface where you can review recent activity, check the status of your devices, and quickly spot any issues.

<p align="center">
  <img src="images/menubar-icons.png" alt="Menu Bar Icons" width="420">
</p>

The cloud icon automatically changes to reflect the current synchronization status, making it easy to see whether everything is synced, synchronization is in progress, or something needs your attention.

CloudStatus isn't meant to replace Syncthing—it's designed to make Syncthing easier to understand.

---

## Features

CloudStatus is built to feel at home on macOS while showing only the information that truly matters.

- Two operating modes (Distributed Mode and Cloud Mode) that automatically adapt both the synchronization logic and the interface to the way you use Syncthing.
- A simple menu bar cloud icon that clearly reflects your synchronization status.
- Recent synchronization activity.
- Status of all connected devices.
- Visual detection of synchronization issues and potential problems.
- Full support for macOS Light and Dark Mode.
- Simple, straightforward configuration.

---

## Why two modes?

Not everyone uses Syncthing the same way.

Some people prefer a fully distributed network where every device works as an equal peer, while others rely on a central server as their primary synchronization hub.

That's why CloudStatus offers two operating modes.

The selected mode doesn't just change how synchronization is interpreted—it also automatically adjusts the interface to highlight the information that's most relevant for your workflow.

<p align="center">

  <img src="images/view-mode.png" alt="Distributed Mode" width="700">

</p>

### Distributed Mode

Designed for people who use Syncthing as a distributed network across multiple devices.

In this mode, the menu bar cloud reflects the overall synchronization status across every device. Recent activity and device organization provide a network-wide view of your synchronization.

### Cloud Mode

Designed for people who use a central server as their primary synchronization point.

It's a workflow similar to Dropbox, OneDrive, or iCloud—but powered entirely by your own infrastructure.

In this mode, CloudStatus treats the server as the point of reference. The menu bar cloud, recent activity, and device organization automatically adapt to provide a server-centric view of your entire synchronization setup.

---

## Philosophy

CloudStatus is designed to blend naturally into macOS with a clean interface where every element serves a purpose. Rather than exposing technical details, it translates Syncthing's status into plain language, so you can understand what's happening with a quick glance.

**Less data. More clarity.**

<p align="center">
  <img src="images/incoming.png" width="450">
</p>

The activity view shows only the information you need to understand what's happening, without cluttering the interface with technical details.

<p align="center">
  <img src="images/computer-folder.png" width="550">
</p>

The Devices section follows the same philosophy. With a single click, you can quickly see which folders each device is sharing.

<p align="center">
  <img src="images/settings.png" width="450">
</p>

Settings are designed the same way: simple, well organized, and fully integrated with the macOS experience.

---

## Before you get started

To use CloudStatus, you'll need:

- macOS 12 Monterey or later.
- Syncthing installed and configured.

---

## Looking ahead

CloudStatus will continue to evolve, always guided by the same philosophy: making Syncthing easier to understand.

Here are a few ideas I'd like to explore in future releases:

- Remote synchronization confirmation using Syncthing's external API.
- Notifications when synchronization conflicts are detected.
- Finder integration to display synchronization status directly on your folders.
- Optional custom icons for shared Syncthing folders.
- Quick access to synchronized folders directly from each device shown in the app.
- A more complete and intuitive first-run setup assistant.
- Notifications when new versions of CloudStatus are available.

As always, every new feature will only be added if it helps make Syncthing a little easier to understand.

---

## A thank you to Syncthing

CloudStatus wouldn't exist without Syncthing.

Discovering Syncthing was one of those rare moments when you stumble upon something truly special. It's an incredible piece of software built around values I deeply believe in: ownership of your own data, privacy, and independence from third-party services.

CloudStatus was born out of that admiration.

My goal has never been to replace Syncthing or compete with it. Quite the opposite. The only objective has been to provide a simpler, more intuitive way to interpret the information Syncthing already provides—especially for day-to-day use.

If you've made it this far without knowing about Syncthing, I highly encourage you to give it a try. And if you're already part of its community, I hope CloudStatus becomes a companion that makes the experience even better.

---

## Buy me a coffee

<p align="center">

  <img src="images/buy-me-coffee.png" alt="Buy Me a Coffee" width="350">

</p>

CloudStatus is a personal project developed in my spare time, and it will always be completely free.

If you find it useful and would like to support its development, you can buy me a coffee. It would be a wonderful way to help me continue dedicating time to the project and making it even better.

Thank you for giving CloudStatus a try.

---

## Acknowledgements

I'd also like to thank ChatGPT. Throughout the development of CloudStatus, it has been an incredible companion—helping me shape hundreds of ideas, solve problems, review code, and write this documentation. I'm convinced this project wouldn't be what it is today without that collaboration.

---

## License

CloudStatus is released under the MIT License.

See the `LICENSE` file for more information.
