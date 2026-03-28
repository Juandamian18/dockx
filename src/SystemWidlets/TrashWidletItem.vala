/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.TrashWidletItem : ContainerItem {
    private const uint REFRESH_INTERVAL_SECONDS = 3;
    private const string ACTION_GROUP_PREFIX = "trash";
    private const string ACTION_PREFIX = ACTION_GROUP_PREFIX + ".";
    private const string EMPTY_ACTION = "empty";
    private const string TRASH_URI = "trash:///";
    private const string TRASH_EMPTY_ICON = "/io/elementary/dock/widlet-icons/trash-empty-image.png";
    private const string TRASH_FULL_ICON = "/io/elementary/dock/widlet-icons/trash-full-image.png";

    private Gtk.Image icon_image;
    private SimpleAction empty_trash_action;
    private uint refresh_timeout_id = 0;
    private bool trash_has_items = false;

    public TrashWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        add_css_class ("trash-widlet-item");

        var action_group = new SimpleActionGroup ();
        empty_trash_action = new SimpleAction (EMPTY_ACTION, null);
        empty_trash_action.activate.connect (() => empty_trash ());
        action_group.add_action (empty_trash_action);
        insert_action_group (ACTION_GROUP_PREFIX, action_group);

        var menu = new Menu ();
        menu.append (_("Empty Trash"), ACTION_PREFIX + EMPTY_ACTION);

        popover_menu = new Gtk.PopoverMenu.from_model (menu) {
            autohide = true,
            position = TOP
        };
        popover_menu.set_offset (0, -1);
        popover_menu.set_parent (this);

        icon_image = new Gtk.Image.from_resource (TRASH_EMPTY_ICON) {
            pixel_size = 44,
            halign = CENTER,
            valign = CENTER,
            can_target = false
        };
        icon_image.add_css_class ("trash-widlet-icon");

        var content = new Gtk.Box (HORIZONTAL, 0) {
            halign = CENTER,
            valign = CENTER,
            can_target = false
        };
        content.append (icon_image);
        child = content;

        gesture_click.button = 0;
        gesture_click.released.connect (on_click_released);

        refresh_trash_state ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_trash_state ();
            return Source.CONTINUE;
        });
    }

    ~TrashWidletItem () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }

        popover_menu.unparent ();
        popover_menu.dispose ();
    }

    private void on_click_released (int n_press, double x, double y) {
        var current_button = gesture_click.get_current_button ();
        if (current_button == Gdk.BUTTON_PRIMARY) {
            popover_menu.popdown ();
            popover_tooltip.popdown ();
            open_trash ();
            return;
        }

        if (current_button != Gdk.BUTTON_SECONDARY) {
            return;
        }

        popover_tooltip.popdown ();
        if (popover_menu.visible) {
            popover_menu.popdown ();
            return;
        }

        popover_menu.popup ();
    }

    private void open_trash () {
        try {
            AppInfo.launch_default_for_uri (TRASH_URI, null);
        } catch (Error e) {
            warning ("Failed to open trash URI: %s", e.message);
        }
    }

    private void empty_trash () {
        popover_menu.popdown ();

        try {
            Process.spawn_command_line_async ("gio trash --empty");
        } catch (Error e) {
            warning ("Failed to empty trash: %s", e.message);
            return;
        }

        Timeout.add (400, () => {
            refresh_trash_state ();
            return Source.REMOVE;
        });
    }

    private void refresh_trash_state () {
        trash_has_items = detect_trash_items ();
        icon_image.set_from_resource (trash_has_items ? TRASH_FULL_ICON : TRASH_EMPTY_ICON);
        empty_trash_action.set_enabled (trash_has_items);
        tooltip_text = trash_has_items ? _("Trash (Contains files)") : _("Trash (Empty)");
    }

    private static bool detect_trash_items () {
        var trash_files_dir = Path.build_filename (Environment.get_home_dir (), ".local", "share", "Trash", "files");

        try {
            var dir = Dir.open (trash_files_dir, 0);
            string? entry_name = null;
            while ((entry_name = dir.read_name ()) != null) {
                var name = entry_name.strip ();
                if (name != "" && name != "." && name != "..") {
                    return true;
                }
            }
        } catch (Error e) {
            return false;
        }

        return false;
    }
}
