// This file is intentionally left blank.
// Its presence in the (app) group was causing a routing conflict with the
// actual login page at /(auth)/login. Removing its content resolves the error.
export default function ConflictingLoginPage() {
  return null;
}
