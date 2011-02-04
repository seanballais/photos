/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Spit.Publishing {

public errordomain PublishingError {
    NO_ANSWER,
    COMMUNICATION_FAILED,
    PROTOCOL_ERROR,
    SERVICE_ERROR,
    MALFORMED_RESPONSE,
    LOCAL_FILE_ERROR,
    EXPIRED_SESSION
}

public interface Publisher : GLib.Object {
    public enum MediaType {
        NONE =          0,
        PHOTO =         1 << 0,
        VIDEO =         1 << 1
    }
    
    public abstract string get_service_name();
    
    public abstract string get_user_visible_name();
    
    public abstract MediaType get_supported_media();
    
    public abstract void start(PublishingInteractor interactor);
    
    public abstract bool is_running();
    
    /* plugins must relinquish their interactor reference when stop( ) is called */
    public abstract void stop();
}

public interface PublishingDialogPane : GLib.Object {
    public enum GeometryOptions {
        NONE =          0,
        EXTENDED_SIZE = 1 << 0,
        RESIZABLE =     1 << 1;
    }
    
    public abstract Gtk.Widget get_widget();
    
	/* the publishing dialog may give you what you want; then again, it may not ;-) */
    public abstract GeometryOptions get_preferred_geometry();
    
    public abstract void on_pane_installed();
    
    public abstract void on_pane_uninstalled();
}

/* fraction_complete should be between 0.0 and 1.0 inclusive */
public delegate void ProgressCallback(int file_number, double fraction_complete);

public delegate void LoginCallback();

public interface PublishingInteractor : GLib.Object {
    public enum ButtonMode {
        CLOSE,
        CANCEL
    }

    public abstract void install_dialog_pane(Spit.Publishing.PublishingDialogPane pane); 
	
    public abstract void post_error(Error err);
    
    public abstract void stop_publishing();
    
    public abstract void install_static_message_pane(string message);
    
    public abstract void install_pango_message_pane(string markup);
    
    public abstract void install_success_pane(Spit.Publishing.Publisher.MediaType media_type);
    
    public abstract void install_account_fetch_wait_pane();
    
    public abstract void install_login_wait_pane();
    
    public abstract void install_welcome_pane(string welcome_message,
        LoginCallback on_login_clicked);
	
    public abstract void set_service_locked(bool locked);
    
    public abstract void set_button_mode(ButtonMode mode);
    
    public abstract void set_dialog_default_widget(Gtk.Widget widget);
    
    public abstract int get_config_int(string key, int default_value);
    
    public abstract string? get_config_string(string key, string? default_value);
    
    public abstract bool get_config_bool(string key, bool default_value);
    
    public abstract double get_config_double(string key, double default_value);
    
    public abstract void set_config_int(string key, int value);
    
    public abstract void set_config_string(string key, string value);
    
    public abstract void set_config_bool(string key, bool value);
    
    public abstract void set_config_double(string key, double value);
    
    public abstract Publishable[] get_publishables();
    
    public abstract ProgressCallback? serialize_publishables(int content_major_axis,
        bool strip_metadata = false);
    
    public abstract Spit.Publishing.Publisher.MediaType get_publishable_media_type();
}

public interface Publishable : GLib.Object {
    public abstract GLib.File serialize_for_publishing(int content_major_axis,
        bool strip_metadata = false) throws Spit.Publishing.PublishingError;
    
    public abstract GLib.File? get_serialized_file();

    public abstract string get_publishing_name();

    public abstract string get_publishing_description();

    public abstract string[] get_publishing_keywords();

    public abstract Spit.Publishing.Publisher.MediaType get_media_type();
}

}