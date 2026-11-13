# Applied after a-first (name order) and after the packages, so it can read
# and override both.
_final: prev: {
  omninixOrder = prev.omninixOrder ++ ["b"];
  hello-fixture = prev.hello-fixture // {overridden = true;};
}
