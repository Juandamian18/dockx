/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.CpuWidletItem : ContainerItem {
    private const uint REFRESH_INTERVAL_SECONDS = 1;

    private Gtk.Label value_label;
    private Gtk.Box fill_overlay;
    private uint refresh_timeout_id = 0;
    private bool has_previous_sample = false;
    private uint64 previous_total = 0;
    private uint64 previous_idle = 0;
    private string current_fill_class = "";

    public CpuWidletItem () {
        Object (disallow_dnd: true, group: Group.WORKSPACE);
    }

    construct {
        add_css_class ("cpu-widlet-item");

        var title_label = new Gtk.Label ("CPU") {
            xalign = 0
        };
        title_label.add_css_class ("usage-widlet-title");

        value_label = new Gtk.Label ("0%") {
            xalign = 0.5f
        };
        value_label.add_css_class ("usage-widlet-value");

        var top_spacer = new Gtk.Box (VERTICAL, 0) {
            vexpand = true
        };
        var bottom_spacer = new Gtk.Box (VERTICAL, 0) {
            vexpand = true
        };

        var text_box = new Gtk.Box (VERTICAL, 0) {
            halign = FILL,
            valign = FILL,
            margin_start = 4,
            margin_end = 4,
            margin_top = 3,
            margin_bottom = 3,
            can_target = false
        };
        text_box.append (title_label);
        text_box.append (top_spacer);
        text_box.append (value_label);
        text_box.append (bottom_spacer);

        fill_overlay = new Gtk.Box (HORIZONTAL, 0) {
            halign = FILL,
            valign = END,
            height_request = 22,
            margin_start = -4,
            margin_end = -4,
            can_target = false
        };
        fill_overlay.add_css_class ("usage-widlet-fill");

        var icon = new Gtk.Image.from_resource ("/io/elementary/dock/widlet-icons/cpu-image.png") {
            pixel_size = 42,
            halign = END,
            valign = END,
            can_target = false
        };
        icon.add_css_class ("usage-widlet-icon");

        var content = new Gtk.Overlay () {
            child = new Gtk.Box (HORIZONTAL, 0),
            overflow = HIDDEN
        };
        content.add_css_class ("usage-widlet-content");
        content.add_overlay (fill_overlay);
        content.set_measure_overlay (fill_overlay, false);
        content.add_overlay (icon);
        content.set_measure_overlay (icon, false);
        content.add_overlay (text_box);
        content.set_measure_overlay (text_box, false);

        child = content;

        update_usage (0);
        refresh_usage ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_usage ();
            return Source.CONTINUE;
        });
    }

    ~CpuWidletItem () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }
    }

    private void refresh_usage () {
        uint64 total = 0;
        uint64 idle = 0;
        if (!read_cpu_sample (out total, out idle)) {
            return;
        }

        if (has_previous_sample && total > previous_total) {
            var total_delta = (double) (total - previous_total);
            var idle_delta = (double) (idle - previous_idle);

            if (total_delta > 0) {
                var usage = (int) Math.round ((1.0 - (idle_delta / total_delta)) * 100.0);
                update_usage (clamp_percentage (usage));
            }
        }

        previous_total = total;
        previous_idle = idle;
        has_previous_sample = true;
    }

    private void update_usage (int usage_percent) {
        value_label.label = "%d%%".printf (usage_percent);
        tooltip_text = "CPU %d%%".printf (usage_percent);
        set_fill_class (get_fill_class_for_percentage (usage_percent));
    }

    private void set_fill_class (string css_class) {
        if (current_fill_class != "") {
            fill_overlay.remove_css_class (current_fill_class);
        }

        fill_overlay.add_css_class (css_class);
        current_fill_class = css_class;
    }

    private static string get_fill_class_for_percentage (int usage_percent) {
        if (usage_percent >= 80) {
            return "usage-widlet-fill-high";
        }
        if (usage_percent >= 50) {
            return "usage-widlet-fill-medium";
        }

        return "usage-widlet-fill-low";
    }

    private static int clamp_percentage (int value) {
        if (value < 0) {
            return 0;
        }
        if (value > 100) {
            return 100;
        }

        return value;
    }

    private static bool read_cpu_sample (out uint64 total, out uint64 idle_total) {
        total = 0;
        idle_total = 0;

        string contents = "";
        try {
            if (!FileUtils.get_contents ("/proc/stat", out contents)) {
                return false;
            }
        } catch (Error e) {
            return false;
        }

        foreach (var raw_line in contents.split ("\n")) {
            var line = raw_line.strip ();
            if (!line.has_prefix ("cpu ")) {
                continue;
            }

            var parts = line.split (" ");
            uint64[] values = {};

            foreach (var raw_part in parts) {
                var part = raw_part.strip ();
                if (part == "" || part == "cpu") {
                    continue;
                }

                if (!Regex.match_simple ("^[0-9]+$", part)) {
                    continue;
                }

                values += uint64.parse (part);
            }

            if (values.length < 4) {
                return false;
            }

            foreach (var value in values) {
                total += value;
            }

            idle_total = values[3];
            if (values.length > 4) {
                idle_total += values[4]; // iowait
            }

            return true;
        }

        return false;
    }
}
