
//${start.app.package}
package com.blitzmax.android;
//${end.app.package}
import org.libsdl.app.SDLActivity;

public class BlitzMaxApp extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "${app.id}" };
    }
}
