# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Ice removed an item](#ice-removed-an-item)
- [Ice does not remember the order of items](#ice-does-not-remember-the-order-of-items)
- [How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-ice-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)

## Items are moved to the always-hidden section

By default, macOS adds new items to the far left of the menu bar, which is also the location of Ice's always-hidden section. Most apps are configured
to remember the positions of their items, but some are not. macOS treats the items of these apps as new items each time they appear. This results in
these items appearing in the always-hidden section, even if they have been previously been moved.

Ice does not currently restore every menu bar item to its previous position
after macOS moves it. Follow current work in the
[roadmap](README.md#featuresroadmap).

## Ice removed an item

Ice does not have the ability to move or remove items. It likely got placed in the always-hidden section by macOS. Option + click the Ice icon to show
the always-hidden section, then Command + drag the item into a different section.

## Ice does not remember the order of items

This is a missing feature rather than a bug. Check this repository's
[roadmap](README.md#featuresroadmap) for current progress.

## How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?

1. Open `System Settings` on your Mac
2. Go to `Control Center`
3. Select `Never` as shown in the image below
4. Update your `Menu Bar Items` in `Ice`
5. Return `Automatically hide and show the menu bar` to your preferred settings

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)
