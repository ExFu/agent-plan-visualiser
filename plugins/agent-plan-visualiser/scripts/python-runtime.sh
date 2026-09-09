# Source from a toolchain script, then apv_resolve_python [required modules].
# Bootstrap requires only standard-library Python; dependencies are checked
# by the resolver before any project writes happen.
apv_resolve_python() {
  APV_PYTHON="$(python3 "$(dirname "${BASH_SOURCE[0]}")/apv_runtime.py" "$@")" || return 2
  export APV_PYTHON
}
