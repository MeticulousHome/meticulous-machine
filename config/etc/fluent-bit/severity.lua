-- Map systemd numeric priority (0-7) to human-readable severity label
-- Matches the same mapping used server-side in fluentd's fluent.conf

local severity_map = {
    [0] = "emerg",
    [1] = "alert",
    [2] = "crit",
    [3] = "err",
    [4] = "warning",
    [5] = "notice",
    [6] = "info",
    [7] = "debug"
}

function add_severity(tag, timestamp, record)
    local priority = record["priority"]
    if priority ~= nil then
        local p = tonumber(priority)
        if p ~= nil and severity_map[p] then
            record["severity"] = severity_map[p]
        else
            record["severity"] = tostring(priority)
        end
    else
        record["severity"] = "unknown"
    end
    return 1, timestamp, record
end
