package hev.socks5;

public final class Socks5Service {

    private Socks5Service() {}

    static {
        System.loadLibrary("hev-socks5-server");
    }

    private static native boolean Socks5StartService(
            String configPath
    );

    private static native boolean Socks5StopService();

    private static native boolean Socks5IsRunning();

    public static boolean start(
            String configPath
    ) {
        return Socks5StartService(
                configPath
        );
    }

    public static boolean stop() {
        return Socks5StopService();
    }

    public static boolean isRunning() {
        return Socks5IsRunning();
    }
}