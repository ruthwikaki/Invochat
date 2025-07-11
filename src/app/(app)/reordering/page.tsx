
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function ReorderingPage() {
  return (
     <AppPage>
        <AppPageHeader 
            title="Feature Moved"
            description="Reorder Suggestions are now part of a more comprehensive report."
        />
        <div className="text-center text-muted-foreground p-8 border-2 border-dashed rounded-lg">
            <h3 className="text-lg font-semibold">This page has moved.</h3>
            <p>You can find our enhanced Reorder Report under the "Reports" section in the navigation.</p>
        </div>
    </AppPage>
  );
}
