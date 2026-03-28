/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2025 elementary, Inc. (https://elementary.io)
 */

public class Dock.WorkspaceIconGroup : BaseIconGroup, WorkspaceItem {
    public Workspace workspace { get; construct; }

    public GLib.ListStore additional_icons { private get; construct; }

    public int workspace_index { get { return workspace.index; } }

    public WorkspaceIconGroup (Workspace workspace) {
        var additional_icons = new GLib.ListStore (typeof (GLib.Icon));

        var workspace_icons = new Gtk.MapListModel (workspace.windows, (window) => {
            return ((Window) window).icon;
        });

        var icon_sources_list_store = new GLib.ListStore (typeof (GLib.ListModel));
        icon_sources_list_store.append (additional_icons);
        icon_sources_list_store.append (workspace_icons);

        var flatten_model = new Gtk.FlattenListModel (icon_sources_list_store);

        Object (
            workspace: workspace,
            additional_icons: additional_icons,
            icons: flatten_model,
            group: Group.WORKSPACE
        );
    }

    construct {
        var create_workspace_button = new Gtk.Button.with_label (_("Create Workspace")) {
            halign = FILL
        };
        create_workspace_button.add_css_class ("flat");
        create_workspace_button.clicked.connect (() => {
            popover_menu.popdown ();
            WorkspaceSystem.get_default ().create_workspace.begin ();
        });

        var menu_content = new Gtk.Box (VERTICAL, 0) {
            margin_start = 6,
            margin_end = 6,
            margin_top = 6,
            margin_bottom = 6
        };
        menu_content.append (create_workspace_button);

        popover_menu = new Gtk.Popover () {
            autohide = true,
            position = TOP,
            child = menu_content
        };
        popover_menu.set_offset (0, -1);
        popover_menu.set_parent (this);

        workspace.bind_property ("is-active-workspace", this, "state", SYNC_CREATE, (binding, from_value, ref to_value) => {
            var new_val = from_value.get_boolean () ? State.ACTIVE : State.HIDDEN;
            to_value.set_enum (new_val);
            return true;
        });

        workspace.removed.connect (() => removed ());

        gesture_click.button = 0;
        gesture_click.released.connect ((n_press, x, y) => {
            switch (gesture_click.get_current_button ()) {
                case Gdk.BUTTON_PRIMARY:
                    workspace.activate ();
                    break;
                case Gdk.BUTTON_SECONDARY:
                    popover_menu.popup ();
                    popover_tooltip.popdown ();
                    break;
            }
        });

        notify["moving"].connect (on_moving_changed);
    }

    ~WorkspaceIconGroup () {
        if (popover_menu != null) {
            popover_menu.unparent ();
            popover_menu.dispose ();
        }
    }

    private void on_moving_changed () {
        if (!moving) {
            workspace.reorder (ItemManager.get_default ().get_index_for_launcher (this));
        }
    }

    public void window_entered (Window window) {
        if (window.workspace_index == workspace.index) {
            return;
        }

        additional_icons.append (window.icon);
        set_state_flags (DROP_ACTIVE, false);
    }

    public void window_left () {
        additional_icons.remove_all ();
        unset_state_flags (DROP_ACTIVE);
    }
}
