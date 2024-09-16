jq -R -s '                                                                                                                        ░▒▓ ✔  took 16s  at 10:48:57 AM ▓▒░
  split("\n")
  | map(select(length > 0))
  | map(
      split("|")
      | {
          device_id: .[0],
          tag_info: (
            .[1]
            | rtrimstr("]")
            | ltrimstr("[(")
            | split("),(")
            | map(
                split(",")
                | {id: .[0], annotation: .[1], timestamp: .[2]}
              )
          )
        }
    )
' tags_by_device.csv >output.json
