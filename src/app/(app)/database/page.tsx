
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { getDatabaseSchemaAndData } from '@/app/data-actions';
import { DataTable } from '@/components/ai-response/data-table';
import { Database } from 'lucide-react';

export default async function DatabaseExplorerPage() {
  const schemaData = await getDatabaseSchemaAndData();

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Database Explorer</h1>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Database className="h-5 w-5" /> Live Database View</CardTitle>
          <CardDescription>
            A direct view of the tables in your database and a preview of their data. This helps verify data imports and see exactly what the AI has access to query.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {schemaData.length > 0 ? (
            <Accordion type="single" collapsible className="w-full">
              {schemaData.map(({ tableName, rows }) => (
                <AccordionItem value={tableName} key={tableName}>
                  <AccordionTrigger className="text-lg font-medium capitalize">{tableName.replace(/_/g, ' ')}</AccordionTrigger>
                  <AccordionContent>
                    {rows.length > 0 ? (
                      <DataTable data={rows} />
                    ) : (
                      <p className="text-muted-foreground p-4 text-center">This table is empty for your company or could not be loaded.</p>
                    )}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          ) : (
             <p className="text-muted-foreground p-4 text-center">Could not load any tables from the database.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
