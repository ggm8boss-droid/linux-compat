# GNU `date -d STRING` -> BSD date options.
# Sets reply to options that go before any +FORMAT, e.g.
#   "2 days ago"          -> (-v-2d)
#   "2024-01-31 10:00"    -> (-j -f '%Y-%m-%d %H:%M:%S' '2024-01-31 10:0:0')
#   "next monday"         -> (-v+1d -v+mon -v0H -v0M -v0S)
#   "@1700000000"         -> (-r 1700000000)
# Returns 1 if the string isn't understood.
_lc_date_args() {
  emulate -L zsh
  setopt extended_glob
  local s=${(L)1} t n u i=1
  local -a head abs adj post tok
  local -A U W
  U=(s S sec S secs S second S seconds S m M min M mins M minute M minutes M
     h H hour H hours H d d day d days d w w week w weeks w
     month m months m y y year y years y)
  W=(sunday sun sun sun monday mon mon mon tuesday tue tue tue tues tue
     wednesday wed wed wed thursday thu thu thu thur thu thurs thu
     friday fri fri fri saturday sat sat sat)
  reply=()

  s=${s//,/ }
  s=${${s##[[:space:]]#}%%[[:space:]]#}

  if [[ $s =~ '^@(-?[0-9]+)(\.[0-9]+)?(.*)$' ]]; then
    head=(-r $match[1]); s=$match[3]
  elif [[ $s =~ '^([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})([t ]+([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?(\.[0-9]+)?)?(z|utc)?(.*)$' ]]; then
    head=(-j)
    abs=(-f '%Y-%m-%d %H:%M:%S' "$match[1]-$match[2]-$match[3] ${match[5]:-0}:${match[6]:-0}:${match[8]:-0}")
    s=$match[11]
  elif [[ $s =~ '^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})(.*)$' ]]; then
    head=(-j)
    abs=(-f '%Y-%m-%d %H:%M:%S' "$match[3]-$match[1]-$match[2] 0:0:0")
    s=$match[4]
  fi

  # Bare time of day: "10:30", "today 23:59:59".
  if [[ $s =~ '(^|[[:space:]])([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?($|[[:space:]])' ]]; then
    post+=(-v$(( 10#$match[2] ))H -v$(( 10#$match[3] ))M -v$(( 10#${match[5]:-0} ))S)
    s=${s/$match[2]:$match[3]${match[4]}/}
  fi

  # "3days" -> "3 days", "+1day" -> "+1 day"
  s=${s//(#b)([0-9])([a-z])/$match[1] $match[2]}
  tok=(${=s})

  while (( i <= $#tok )); do
    t=$tok[i]
    case $t in
      now|today|and|this) ;;
      yesterday) adj+=(-1d);;
      tomorrow)  adj+=(+1d);;
      midnight)  post+=(-v0H -v0M -v0S);;
      noon)      post+=(-v12H -v0M -v0S);;
      ago)       adj=(${adj/#+/@}); adj=(${adj/#-/+}); adj=(${adj/#@/-});;
      next|last)
        (( i++ )); u=$tok[i]
        n=+; [[ $t == last ]] && n=-
        if (( $+U[$u] )); then
          adj+=(${n}1$U[$u])
        elif (( $+W[$u] )); then
          adj+=(${n}1d); post+=(-v$n$W[$u] -v0H -v0M -v0S)
        else
          return 1
        fi;;
      [+-](#c0,1)[0-9]##)
        n=$t; [[ $n == [+-]* ]] || n=+$n
        u=$tok[i+1]
        if (( $+U[$u] )); then
          (( i++ )); adj+=($n$U[$u])
        else
          return 1
        fi;;
      *)
        if (( $+U[$t] )); then adj+=(+1$U[$t])
        elif (( $+W[$t] )); then post+=(-v+$W[$t] -v0H -v0M -v0S)
        else return 1
        fi;;
    esac
    (( i++ ))
  done

  reply=($head ${adj/#/-v} $post $abs)
  return 0
}
