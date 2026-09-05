package hev.htproxy;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class TProxyService {

    private TProxyService() {
    }

    private static native boolean TProxyStartService(
            String configPath,
            int fd
    );

    private static native boolean TProxyStopService();

    private static native boolean TProxyIsRunning();

    private static native long[] TProxyGetStats();

    private static native Map[] TProxyGetFlows();

    static {
        System.loadLibrary("hev-socks5-tunnel");
    }

    public static boolean start(
            String configPath,
            int fd
    ) {
        return TProxyStartService(
                configPath,
                fd
        );
    }

    public static boolean stop() {
        return TProxyStopService();
    }

    public static boolean isRunning() {
        return TProxyIsRunning();
    }

    public static long[] stats() {
        long[] value = TProxyGetStats();

        if (value == null) {
            return new long[0];
        }

        return value;
    }

    @SuppressWarnings("unchecked")
    public static List<Map<String, Object>> getFlows() {

        Map[] raw = TProxyGetFlows();

        List<Map<String, Object>> result =
                new ArrayList<>();

        if (raw == null) {
            return result;
        }

        for (Map item : raw) {

            if (item == null) {
                continue;
            }

            Map<String, Object> copy =
                    new HashMap<>();

            for (Object key : item.keySet()) {

                if (key != null) {

                    copy.put(
                            String.valueOf(key),
                            item.get(key)
                    );
                }
            }

            result.add(copy);
        }

        return result;
    }
}