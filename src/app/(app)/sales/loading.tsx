import { TablePageSkeleton } from "@/components/skeletons/table-page-skeleton";

export default function SalesLoading() {
  return (
    <TablePageSkeleton 
        title="Sales History"
        description="View and manage all recorded sales orders."
    />
  );
}
