# !/bin/bash

# ===== STEP: FILL IN ========
# FROM:
from_username=your-username-source
from_token=your-token-source
# TO:
to_username=your-username-destiny
to_token=your-token-destiny
# =================


# ===== STEP: SET VARIABLES, FUNCTIONS & DEFAULTS ========
base_url="https://api.github.com/"

from_request_header="curl -sH \"Authorization: token ${from_token}\""
from_user_url="${base_url}users/${from_username}/"
from_user_gists_url="${from_user_url}gists"

to_request_header="curl -sH \"Authorization: token ${to_token}\""
gists_url="${base_url}gists/"

# set $msg written at forkingMsg function as global
# this will make it accessible to the interrupt_forking function
# that will be fired if user ctrl+c during the forking
msg=""

# args: partial_response
if_bad_credentials_quit() {
  bad_credentials=$(grep 'Bad credentials' <<< "${partial_response}")
  if [[ "${bad_credentials}" ]]; then
    echo " failed"
    echo "Bad credentials"
    exit 0
  fi
}

#args: partial_response
if_empty_response_complete() {
  # if no more results, api will return '[]' filled with two whitespaces
  # I couldn't identify which ones; thats why I used posix character classes
  if [[ "${partial_response}" =~ "["[[:space:]]{2}"]" ]]; then
    return 0
  fi

  return 1
}

# args: index, gists_quant
forkingMsg() {
  # first cur will be 1 and last will be equal to gists_quant
  cur=$(("${2} - ${1}"))
  msg="Forking gist ${cur}/${2}..."
  echo -ne "${msg}"'\r'

  # only will add a newline at the last index
  # '$2 + 1' is needed because the array index starts at 0
  if [[ "${1}" -eq 0 ]]; then
    echo "${msg} ok"
  fi
}

endMsg() {
  echo "=========="
  echo "${from_username}'s ${1} gists forked to ${to_username}'s acount!"
}

interrupt_forking() {
  echo "${msg} ok"
  echo "canceled by the user, won't continue"
  gists_forked_quant=$(echo "${msg}" | awk '{ print $3 }' | awk -F '/' '{ print $1 }')
  endMsg "${gists_forked_quant}"
  exit 0
}

# doesn't output '^C' after press ctrl+c
stty -echoctl


# ===== STEP: GET GISTS INFO ========
echo -n "Getting gists info from source..."

declare -i page
page=1
# colon is the no-op (do-nothing) command; while will keep running until break
while [[ : ]]; do
  request="${from_request_header} \"${from_user_gists_url}?page=${page}&per_page=100\""
  partial_response=$(eval "${request}")

  if_bad_credentials_quit "${partial_response}"

  # if current response is empty, get out of the loop
  if_empty_response_complete "${partial_response}" && break

  # append responses
  response="${response}${partial_response}"

  page="${page}"+1
done

echo " ok"


# ===== STEP: SAVE INFO IN ARRAYS ========
# each property will be saved in a separate array
# info about a specific gist will be stored at the same index in every array
declare -a gists_urls_arr
# mapfile -t gists_urls_arr < <(grep -o '"git_push_url": "https://gist.github.com/[a-z0-9]*.git"' <<< "${response}" | awk '{ print $2 }')
mapfile -t gists_urls_arr < <(grep -o '"git_push_url": "https://gist.github.com/[a-z0-9]*.git"' <<< "${response}" | sed 's/.*com\/\(.*\)\.git\"/\1/g')

gists_quant="${#gists_urls_arr[@]}"


# ===== STEP: FORKING ========
# handle ctrl+c (if keys are pressed after the execution of this line of the code)
trap interrupt_forking SIGINT

# index order is last to first
# this will make sure that the gists are forked in the same order as they're created
declare -i index
# subtraction is needed because array starts at 0
# therefore last elements will be located at (total - 1)
index="${gists_quant} - 1"
while [[ "${index}" -ge 0 ]]; do
  gist_id="${gists_urls_arr[${index}]}"
  fork_url="${gists_url}${gist_id}/forks"
  # "-d ''" is needed to send request as POST
  request="${to_request_header} -d '' ${fork_url}"
  
  # depending at when the user press ctrl+c
  # e.g. forkingMsg execution is done but response isn't completed
  # $msg may be wrong(anticipated), but it doesn't matter
  forkingMsg "${index}" "${gists_quant}"

  response=$(eval "${request}")

  index=$index-1
done

endMsg "${gists_quant}"