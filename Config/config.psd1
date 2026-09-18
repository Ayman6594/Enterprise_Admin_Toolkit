@{
    # Central config so values aren't hardcoded inside functions.
    # As of v1.0 this is minimal; v3.0 (Security) and v4.0 (Monitoring)
    # will add thresholds (e.g. disk usage %, failed logon count) here.

    Network = @{
        ConnectivityTestTargets = @("1.1.1.1", "8.8.8.8")
        DefaultPingCount        = 4
    }

    Logging = @{
        LogFileName   = "toolkit.log"
        MaxLogSizeMB  = 10   # not yet enforced in v1.0 - add log rotation before v3.0
    }
}
