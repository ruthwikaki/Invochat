
import { redirect } from "next/navigation";

// The /settings path itself doesn't have a page,
// it just serves as a layout route. Redirect users
// to the first available settings page.
export default function SettingsRootPage() {
    redirect('/settings/profile');
}
