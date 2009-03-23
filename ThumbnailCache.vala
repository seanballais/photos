
// these functions generate compiler warnings due to Vala not supporting const pointers (yet) ...
// see http://www.mail-archive.com/vala-list@gnome.org/msg00977.html
public uint photo_id_hash(void *key) {
    PhotoID *photoID = (PhotoID *) key;
    
    return (uint) photoID->id;
}

public bool photo_id_equal(void *a, void *b) {
    PhotoID *aID = (PhotoID *) a;
    PhotoID *bID = (PhotoID *) b;
    
    return aID->id == bID->id;
}

public class ThumbnailCache : Object {
    public static const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.HYPER;
    public static const int DEFAULT_JPEG_QUALITY = 90;
    public static const int MAX_INMEMORY_DATA_SIZE = 256 * 1024;
    
    public static const int BIG_SCALE = 360;
    public static const int MEDIUM_SCALE = 128;
    public static const int SMALL_SCALE = 64;

    public static ThumbnailCache big = null;
    public static ThumbnailCache medium = null;
    public static ThumbnailCache small = null;
    
    // Doing this because static construct {} not working nor new'ing in the above statement
    public static void init() {
        big = new ThumbnailCache(BIG_SCALE);
        medium = new ThumbnailCache(MEDIUM_SCALE);
        small = new ThumbnailCache(SMALL_SCALE);
    }
    
    public static Dimensions import(PhotoID photoID, Gdk.Pixbuf original, bool force = false) {
        big._import(photoID, original, force);
        medium._import(photoID, original, force);
        small._import(photoID, original, force);
        
        return Dimensions(original.get_width(), original.get_height());
    }
    
    public static void remove(PhotoID photoID) {
        big._remove(photoID);
        medium._remove(photoID);
        small._remove(photoID);
    }

    private static const int BIG_MED_BREAK = MEDIUM_SCALE + ((BIG_SCALE - MEDIUM_SCALE) / 2);
    private static const int SMALL_MED_BREAK = SMALL_SCALE + ((MEDIUM_SCALE - SMALL_SCALE) / 2);

    public static bool refresh_pixbuf(int oldScale, int newScale) {
        if (oldScale > MEDIUM_SCALE) {
            return (newScale <= MEDIUM_SCALE);
        } else if(oldScale > SMALL_SCALE) {
            return (newScale <= SMALL_SCALE) || (newScale > MEDIUM_SCALE);
        } else {
            return (newScale > SMALL_SCALE);
        }
    }

    public static Gdk.Pixbuf? fetch(PhotoID photoID, int scale) {
        if (scale > MEDIUM_SCALE) {
            return big._fetch(photoID);
        } else if(scale > SMALL_SCALE) {
            return medium._fetch(photoID);
        } else {
            return small._fetch(photoID);
        }
    }
    
    private class ImageData {
        public uchar[] buffer;
        
        public ImageData(uchar[] buffer) {
            this.buffer = buffer;
        }
    }

    private File cacheDir;
    private int scale;
    private Gdk.InterpType interp;
    private string jpegQuality;
    private Gee.HashMap<PhotoID?, ImageData> cacheMap = new Gee.HashMap<PhotoID?, ImageData>(
        photo_id_hash, photo_id_equal, direct_equal);
    private long cachedBytes = 0;
    private ThumbnailCacheTable cacheTable;
    
    private ThumbnailCache(int scale, Gdk.InterpType interp = DEFAULT_INTERP,
        int jpegQuality = DEFAULT_JPEG_QUALITY) {
        assert(scale != 0);
        assert((jpegQuality >= 0) && (jpegQuality <= 100));

        this.cacheDir = AppWindow.get_data_subdir("thumbs", "thumbs%d".printf(scale));
        this.scale = scale;
        this.interp = interp;
        this.jpegQuality = "%d".printf(jpegQuality);
        this.cacheTable = new ThumbnailCacheTable(scale);
    }
    
    private Gdk.Pixbuf? _fetch(PhotoID photoID) {
        // use JPEG in memory cache if available
        ImageData data = cacheMap.get(photoID);
        if (data != null) {
            try {
                MemoryInputStream memins = new MemoryInputStream.from_data(data.buffer, 
                    data.buffer.length, null);
                Gdk.Pixbuf thumbnail = new Gdk.Pixbuf.from_stream(memins, null);

                return thumbnail;
            } catch (Error err) {
                error("%s", err.message);
            }
        }

        // load from disk and then store in memory
        File cached = get_cached_file(photoID);
        debug("Loading from disk [%d] %s", photoID.id, cached.get_path());

        Gdk.Pixbuf thumbnail = null;
        try {
            int filesize = cacheTable.get_filesize(photoID);
            if(filesize > MAX_INMEMORY_DATA_SIZE) {
                // too big to store in memory, so build the pixbuf straight from disk
                debug("%s too large to cache, loading straight from disk", cached.get_path());

                return new Gdk.Pixbuf.from_file(cached.get_path());
            }

            FileInputStream fins = cached.read(null);
            assert(fins != null);

            uchar[] buffer = new uchar[filesize];
            
            size_t bytesRead;
            if (fins.read_all(buffer, filesize, out bytesRead, null) == false) {
                error("Unable to read %d bytes from %s", buffer.length, cached.get_path());
            }
            
            assert(bytesRead == filesize);

            data = new ImageData(buffer);
            cacheMap.set(photoID, data);
            cachedBytes += data.buffer.length;

            MemoryInputStream memins = new MemoryInputStream.from_data(data.buffer, 
                data.buffer.length, null);
            thumbnail = new Gdk.Pixbuf.from_stream(memins, null);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        return thumbnail;
    }
    
    private void _import(PhotoID photoID, Gdk.Pixbuf original, bool force = false) {
        File cached = get_cached_file(photoID);
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (cached.query_exists(null) && cacheTable.exists(photoID))
                return;
        }

        debug("Building persistent thumbnail for [%d] %s", photoID.id, cached.get_path());
        
        // scale according to cache's parameters
        Gdk.Pixbuf thumbnail = scale_pixbuf(original, scale, interp);
        
        // save scaled image as JPEG
        int filesize = -1;
        try {
            if (thumbnail.save(cached.get_path(), "jpeg", "quality", jpegQuality) == false) {
                error("Unable to save thumbnail %s", cached.get_path());
            }

            FileInfo info = cached.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            
            // this should never be huge
            assert(info.get_size() <= int.MAX);
            filesize = (int) info.get_size();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // store in database
        Dimensions dim = Dimensions(thumbnail.get_width(), thumbnail.get_height());
        cacheTable.add(photoID, filesize, dim);
    }
    
    private void _remove(PhotoID photoID) {
        File cached = get_cached_file(photoID);
        
        debug("Removing [%d] %s", photoID.id, cached.get_path());

        if (cacheMap.contains(photoID)) {
            ImageData data = cacheMap.get(photoID);

            assert(cachedBytes >= data.buffer.length);
            cachedBytes -= data.buffer.length;

            // remove from in-memory cache
            cacheMap.remove(photoID);
        }
        
        // remove from db table
        cacheTable.remove(photoID);
 
        // remove from disk
        try {
            if (cached.delete(null) == false) {
                error("Unable to delete cached thumb %s", cached.get_path());
            }
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    private File get_cached_file(PhotoID photoID) {
        return cacheDir.get_child("thumb%08x.jpg".printf(photoID.id));
    }
}
