/*
 * SPDX-License-Identifier: GPL-3.0
 * SPDX-FileCopyrightText: 2026 dockx contributors
 */

public class Dock.WidletAlertController : Object {
    private const string SETTINGS_SCHEMA = "io.elementary.dock";
    private const uint BLINK_INTERVAL_MILLISECONDS = 420;

    private Gtk.Widget target_widget;
    private GLib.Settings settings;
    private string enabled_key;
    private string threshold_key;
    private string alert_id;
    private string widlet_name;
    private string metric_name;
    private string metric_unit;

    private bool is_alerting = false;
    private bool flash_visible = false;
    private uint blink_timeout_id = 0;

    public WidletAlertController (
        Gtk.Widget target_widget,
        string enabled_key,
        string threshold_key,
        string alert_id,
        string widlet_name,
        string metric_name,
        string metric_unit
    ) {
        this.target_widget = target_widget;
        this.enabled_key = enabled_key;
        this.threshold_key = threshold_key;
        this.alert_id = alert_id;
        this.widlet_name = widlet_name;
        this.metric_name = metric_name;
        this.metric_unit = metric_unit;
        settings = new GLib.Settings (SETTINGS_SCHEMA);

        settings.changed.connect ((changed_key) => {
            if (changed_key == enabled_key && !is_enabled ()) {
                clear_alert_state ();
            }
        });
    }

    ~WidletAlertController () {
        clear_alert_state ();
    }

    public bool has_settings_keys () {
        return has_key (enabled_key) && has_key (threshold_key);
    }

    public bool is_enabled () {
        if (!has_key (enabled_key)) {
            return false;
        }

        return settings.get_boolean (enabled_key);
    }

    public int get_threshold (int fallback_threshold) {
        if (!has_key (threshold_key)) {
            return fallback_threshold;
        }

        return settings.get_int (threshold_key);
    }

    public void set_enabled (bool enabled) {
        if (has_key (enabled_key)) {
            settings.set_boolean (enabled_key, enabled);
        }
    }

    public void set_threshold (int threshold) {
        if (has_key (threshold_key)) {
            settings.set_int (threshold_key, threshold);
        }
    }

    public void evaluate_int (int value, bool has_data, int fallback_threshold) {
        var threshold = get_threshold (fallback_threshold);
        var should_alert = has_data && is_enabled () && value >= threshold;

        if (should_alert) {
            if (!is_alerting) {
                start_alert_state (value, threshold);
            }
            return;
        }

        if (is_alerting) {
            clear_alert_state ();
        }
    }

    private void start_alert_state (int current_value, int threshold) {
        is_alerting = true;
        target_widget.add_css_class ("widlet-alert-armed");
        set_flash_visible (true);
        start_blinking ();
        send_notification (current_value, threshold);
    }

    private void clear_alert_state () {
        is_alerting = false;
        stop_blinking ();
        set_flash_visible (false);
        target_widget.remove_css_class ("widlet-alert-armed");
    }

    private void start_blinking () {
        if (blink_timeout_id != 0) {
            Source.remove (blink_timeout_id);
            blink_timeout_id = 0;
        }

        blink_timeout_id = Timeout.add (BLINK_INTERVAL_MILLISECONDS, () => {
            if (!is_alerting) {
                blink_timeout_id = 0;
                return Source.REMOVE;
            }

            set_flash_visible (!flash_visible);
            return Source.CONTINUE;
        });
    }

    private void stop_blinking () {
        if (blink_timeout_id != 0) {
            Source.remove (blink_timeout_id);
            blink_timeout_id = 0;
        }
    }

    private void set_flash_visible (bool visible) {
        flash_visible = visible;
        if (visible) {
            target_widget.add_css_class ("widlet-alert-flash");
        } else {
            target_widget.remove_css_class ("widlet-alert-flash");
        }
    }

    private void send_notification (int current_value, int threshold) {
        var app = GLib.Application.get_default ();
        if (app == null) {
            return;
        }

        var notification = new GLib.Notification (_("%s Alert").printf (widlet_name));
        notification.set_priority (GLib.NotificationPriority.URGENT);
        notification.set_body (_("%s reached %s (threshold %s).").printf (
            metric_name,
            format_metric_value (current_value),
            format_metric_value (threshold)
        ));

        app.send_notification ("widlet-alert-%s".printf (alert_id), notification);
    }

    private string format_metric_value (int value) {
        if (metric_unit == "%") {
            return "%d%%".printf (value);
        }

        return "%d%s".printf (value, metric_unit);
    }

    private bool has_key (string key) {
        return settings.settings_schema.has_key (key);
    }
}
