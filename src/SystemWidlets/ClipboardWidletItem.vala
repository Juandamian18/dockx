/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.ClipboardWidletItem : ContainerItem {
    private const int BASE_ICON_PIXEL_SIZE = 68;
    private const int ICON_SOURCE_WIDTH = 152;
    private const int ICON_SOURCE_HEIGHT = 152;
    private const string MAX_ITEMS_KEY = "widlet-clipboard-max-items";
    private const string PINNED_TEXTS_KEY = "widlet-clipboard-pinned-texts";
    private const string CLIPBOARD_EMPTY_ICON = "/io/elementary/dock/widlet-icons/clipboard-empty.png";
    private const string CLIPBOARD_FULL_ICON = "/io/elementary/dock/widlet-icons/clipboard-full.png";
    private const int DEFAULT_MAX_ITEMS = 20;
    private const int MIN_MAX_ITEMS = 5;
    private const int MAX_MAX_ITEMS = 200;
    private const int MAX_STORED_TEXT_LENGTH = 1200;
    private const int MAX_PINNED_ITEMS = 120;

    private class DetailsPopover : Gtk.Popover {
        class construct {
            set_css_name ("tooltip");
        }
    }

    private Gtk.Image icon_image;

    private Gtk.Label details_subtitle_label;
    private Gtk.Box pinned_items_box;
    private Gtk.Box recent_items_box;
    private Gtk.Label pinned_empty_label;
    private Gtk.Label recent_empty_label;

    private Gdk.Clipboard? clipboard = null;
    private bool ignore_next_clipboard_change = false;
    private uint clipboard_read_serial = 0;
    private int max_history_items = DEFAULT_MAX_ITEMS;
    private bool has_visual_items = false;

    private string[] history_items = {};
    private string[] pinned_items = {};

    public ClipboardWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        add_css_class ("clipboard-widlet-item");

        icon_image = new Gtk.Image.from_resource (CLIPBOARD_EMPTY_ICON) {
            halign = CENTER,
            valign = END,
            can_target = false
        };
        icon_image.add_css_class ("clipboard-widlet-icon");

        var base_surface = new Gtk.Box (HORIZONTAL, 0) {
            can_target = false
        };
        base_surface.add_css_class ("clipboard-widlet-surface");

        var content = new Gtk.Overlay () {
            child = base_surface,
            overflow = HIDDEN
        };
        content.add_css_class ("clipboard-widlet-content");
        content.add_overlay (icon_image);
        content.set_measure_overlay (icon_image, false);

        child = content;

        var details_title = new Gtk.Label (_("Clipboard")) {
            xalign = 0
        };
        details_title.add_css_class ("widlet-details-title");

        details_subtitle_label = new Gtk.Label ("") {
            xalign = 0
        };
        details_subtitle_label.add_css_class (Granite.CssClass.DIM);
        details_subtitle_label.add_css_class (Granite.CssClass.SMALL);
        details_subtitle_label.add_css_class ("clipboard-history-subtitle");

        var pinned_title = new Gtk.Label (_("Pinned Texts")) {
            xalign = 0
        };
        pinned_title.add_css_class ("clipboard-history-section-title");

        pinned_items_box = new Gtk.Box (VERTICAL, 4);

        pinned_empty_label = new Gtk.Label (_("No pinned texts.")) {
            xalign = 0
        };
        pinned_empty_label.add_css_class (Granite.CssClass.DIM);
        pinned_empty_label.add_css_class (Granite.CssClass.SMALL);
        pinned_empty_label.add_css_class ("clipboard-history-empty");

        var recent_title = new Gtk.Label (_("Recent Clipboard")) {
            xalign = 0
        };
        recent_title.add_css_class ("clipboard-history-section-title");

        recent_items_box = new Gtk.Box (VERTICAL, 4);

        recent_empty_label = new Gtk.Label (_("No copied text yet.")) {
            xalign = 0
        };
        recent_empty_label.add_css_class (Granite.CssClass.DIM);
        recent_empty_label.add_css_class (Granite.CssClass.SMALL);
        recent_empty_label.add_css_class ("clipboard-history-empty");

        var sections_box = new Gtk.Box (VERTICAL, 8);
        sections_box.append (pinned_title);
        sections_box.append (pinned_items_box);
        sections_box.append (pinned_empty_label);
        sections_box.append (new Gtk.Separator (HORIZONTAL));
        sections_box.append (recent_title);
        sections_box.append (recent_items_box);
        sections_box.append (recent_empty_label);

        var sections_scroll = new Gtk.ScrolledWindow () {
            child = sections_box,
            hscrollbar_policy = NEVER,
            vscrollbar_policy = AUTOMATIC,
            min_content_height = 120,
            max_content_height = 280
        };

        var details_content = new Gtk.Box (VERTICAL, 8) {
            margin_start = 10,
            margin_end = 10,
            margin_top = 8,
            margin_bottom = 8,
            width_request = 320
        };
        details_content.add_css_class ("widlet-details-popover");
        details_content.append (details_title);
        details_content.append (details_subtitle_label);
        details_content.append (new Gtk.Separator (HORIZONTAL));
        details_content.append (sections_scroll);

        popover_menu = new DetailsPopover () {
            autohide = true,
            position = TOP,
            has_arrow = false,
            child = details_content
        };
        popover_menu.set_offset (0, -1);
        popover_menu.set_parent (this);

        gesture_click.button = 0;
        gesture_click.released.connect (on_click_released);
        notify["icon-size"].connect (update_size_variant);
        update_size_variant ();

        if (dock_settings.settings_schema.has_key (MAX_ITEMS_KEY)) {
            dock_settings.changed[MAX_ITEMS_KEY].connect (() => {
                reload_max_items_from_settings ();
                trim_history_to_max ();
                refresh_state ();
            });
        }
        if (dock_settings.settings_schema.has_key (PINNED_TEXTS_KEY)) {
            dock_settings.changed[PINNED_TEXTS_KEY].connect (() => {
                reload_pinned_items_from_settings ();
                refresh_state ();
            });
        }

        reload_max_items_from_settings ();
        reload_pinned_items_from_settings ();
        setup_clipboard_monitoring ();
        refresh_state ();
    }

    ~ClipboardWidletItem () {
        if (popover_menu != null) {
            popover_menu.unparent ();
            popover_menu.dispose ();
        }
    }

    private void setup_clipboard_monitoring () {
        var display = Gdk.Display.get_default ();
        if (display == null) {
            warning ("Clipboard widlet could not access the default display.");
            return;
        }

        clipboard = display.get_clipboard ();
        clipboard.changed.connect (() => read_clipboard_text.begin ());
        read_clipboard_text.begin ();
    }

    private async void read_clipboard_text () {
        if (clipboard == null) {
            return;
        }

        var request_serial = ++clipboard_read_serial;
        try {
            var text = yield clipboard.read_text_async (null);
            if (request_serial != clipboard_read_serial) {
                return;
            }

            if (ignore_next_clipboard_change) {
                ignore_next_clipboard_change = false;
                return;
            }

            if (text == null) {
                return;
            }

            add_history_item (text);
        } catch (Error e) {
            debug ("Clipboard read failed: %s", e.message);
        }
    }

    private void on_click_released (int n_press, double x, double y) {
        var current_button = gesture_click.get_current_button ();
        if (current_button != Gdk.BUTTON_PRIMARY && current_button != Gdk.BUTTON_SECONDARY) {
            return;
        }

        if (popover_menu.visible) {
            popover_menu.popdown ();
            return;
        }

        popover_tooltip.popdown ();
        refresh_state ();
        popover_menu.popup ();
    }

    private void reload_max_items_from_settings () {
        if (dock_settings.settings_schema.has_key (MAX_ITEMS_KEY)) {
            max_history_items = clamp_int (dock_settings.get_int (MAX_ITEMS_KEY), MIN_MAX_ITEMS, MAX_MAX_ITEMS);
        } else {
            max_history_items = DEFAULT_MAX_ITEMS;
        }
    }

    private void reload_pinned_items_from_settings () {
        if (dock_settings.settings_schema.has_key (PINNED_TEXTS_KEY)) {
            pinned_items = normalize_text_items (dock_settings.get_strv (PINNED_TEXTS_KEY), MAX_PINNED_ITEMS);
        } else {
            pinned_items = {};
        }
    }

    private void add_history_item (string raw_text) {
        var normalized = normalize_clipboard_text (raw_text);
        if (normalized == "") {
            return;
        }

        string[] updated = {normalized};
        foreach (var existing in history_items) {
            if (existing != normalized) {
                updated += existing;
            }
        }

        history_items = updated;
        trim_history_to_max ();
        refresh_state ();
    }

    private void trim_history_to_max () {
        if (max_history_items <= 0 || history_items.length <= max_history_items) {
            return;
        }

        string[] trimmed = {};
        for (int i = 0; i < history_items.length && i < max_history_items; i++) {
            trimmed += history_items[i];
        }

        history_items = trimmed;
    }

    private void refresh_state () {
        var recent_count = history_items.length;
        var total_count = recent_count + pinned_items.length;

        update_visual_state (total_count > 0);
        tooltip_text = total_count > 0
            ? _("Clipboard %d items").printf (recent_count)
            : _("Clipboard (Empty)");

        details_subtitle_label.label = _("%d recent • %d pinned").printf (recent_count, pinned_items.length);
        rebuild_items_list ();
    }

    private void rebuild_items_list () {
        clear_box (pinned_items_box);
        clear_box (recent_items_box);

        foreach (var text in pinned_items) {
            pinned_items_box.append (create_history_row (text, true));
        }
        pinned_empty_label.visible = pinned_items.length == 0;

        var recent = get_recent_items_for_display ();
        foreach (var text in recent) {
            recent_items_box.append (create_history_row (text, false));
        }
        recent_empty_label.visible = recent.length == 0;
    }

    private string[] get_recent_items_for_display () {
        string[] filtered = {};
        foreach (var text in history_items) {
            if (contains_text (pinned_items, text)) {
                continue;
            }

            filtered += text;
        }

        return filtered;
    }

    private Gtk.Widget create_history_row (string text, bool pinned) {
        var row_button = new Gtk.Button () {
            halign = FILL,
            hexpand = true
        };
        row_button.add_css_class ("flat");
        row_button.add_css_class ("clipboard-history-row");

        var preview_label = new Gtk.Label (build_text_preview (text)) {
            xalign = 0,
            hexpand = true,
            single_line_mode = true,
            ellipsize = Pango.EllipsizeMode.END
        };
        preview_label.add_css_class ("clipboard-history-row-label");

        var trailing = new Gtk.Image.from_icon_name (pinned ? "starred-symbolic" : "edit-copy-symbolic") {
            pixel_size = 14,
            halign = END,
            valign = CENTER
        };
        trailing.add_css_class ("clipboard-history-row-icon");

        var row_content = new Gtk.Box (HORIZONTAL, 8) {
            margin_start = 8,
            margin_end = 8,
            margin_top = 6,
            margin_bottom = 6
        };
        row_content.append (preview_label);
        row_content.append (trailing);
        row_button.child = row_content;
        row_button.tooltip_text = text;

        row_button.clicked.connect (() => {
            copy_to_clipboard (text);
            popover_menu.popdown ();
        });

        return row_button;
    }

    private void copy_to_clipboard (string text) {
        if (clipboard != null) {
            ignore_next_clipboard_change = true;
            clipboard.set_text (text);
        }

        add_history_item (text);
    }

    private void update_size_variant () {
        remove_css_class ("widlet-size-small");
        remove_css_class ("widlet-size-large");

        if (icon_size <= 40) {
            add_css_class ("widlet-size-small");
        } else if (icon_size >= 56) {
            add_css_class ("widlet-size-large");
        }

        var scaled = clamp_int ((int) Math.round ((double) BASE_ICON_PIXEL_SIZE * (double) icon_size / 48.0), 42, 96);
        icon_image.width_request = scaled;
        icon_image.height_request = (int) Math.round (((double) scaled * (double) ICON_SOURCE_HEIGHT) / (double) ICON_SOURCE_WIDTH);
    }

    private void update_visual_state (bool has_items) {
        if (has_visual_items == has_items) {
            return;
        }

        has_visual_items = has_items;
        icon_image.set_from_resource (has_items ? CLIPBOARD_FULL_ICON : CLIPBOARD_EMPTY_ICON);

        if (has_items) {
            add_css_class ("clipboard-has-items");
        } else {
            remove_css_class ("clipboard-has-items");
        }
    }

    private static string normalize_clipboard_text (string raw_text) {
        var normalized = raw_text.replace ("\r\n", "\n").replace ("\r", "\n").strip ();
        if (normalized == "") {
            return "";
        }

        if (normalized.length > MAX_STORED_TEXT_LENGTH) {
            normalized = normalized.substring (0, MAX_STORED_TEXT_LENGTH).strip ();
        }

        return normalized;
    }

    private static string[] normalize_text_items (string[] source, int max_items) {
        string[] normalized = {};
        foreach (var raw in source) {
            var text = normalize_clipboard_text (raw);
            if (text == "" || contains_text (normalized, text)) {
                continue;
            }

            normalized += text;
            if (normalized.length >= max_items) {
                break;
            }
        }

        return normalized;
    }

    private static bool contains_text (string[] list, string value) {
        foreach (var item in list) {
            if (item == value) {
                return true;
            }
        }

        return false;
    }

    private static string build_text_preview (string value) {
        var preview = value.replace ("\n", " ⏎ ").strip ();
        if (preview.length > 90) {
            return preview.substring (0, 89) + "…";
        }

        return preview;
    }

    private static void clear_box (Gtk.Box box) {
        var child = box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            box.remove (child);
            child = next;
        }
    }

    private static int clamp_int (int value, int min, int max) {
        if (value < min) {
            return min;
        }

        if (value > max) {
            return max;
        }

        return value;
    }
}
