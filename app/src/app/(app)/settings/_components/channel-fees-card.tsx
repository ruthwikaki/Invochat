
'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm, useFieldArray } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { getChannelFees, upsertChannelFee } from '@/app/data-actions';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Loader2, Trash2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { getErrorMessage } from '@/lib/error-handler';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf-client';

const ChannelFeeSchema = z.object({
  channel_name: z.string().min(1, 'Channel name is required'),
  fixed_fee: z.coerce.number().min(0, 'Fee must be non-negative').optional().nullable(),
  percentage_fee: z.coerce.number().min(0, 'Fee must be non-negative').optional().nullable(),
});

const FormSchema = z.object({
    fees: z.array(ChannelFeeSchema),
});

export function ChannelFeesCard() {
    const queryClient = useQueryClient();
    const { toast } = useToast();

    const { data: channelFees, isLoading } = useQuery({
        queryKey: ['channelFees'],
        queryFn: getChannelFees,
        initialData: [],
    });

    const { register, handleSubmit, control, formState: { errors } } = useForm<z.infer<typeof FormSchema>>({
        resolver: zodResolver(FormSchema),
        values: { fees: channelFees || [] },
    });

    const { fields, append, remove } = useFieldArray({
        control,
        name: "fees"
    });

    const { mutate, isPending } = useMutation({
        mutationFn: async (data: z.infer<typeof ChannelFeeSchema>) => {
            const formData = new FormData();
            Object.entries(data).forEach(([key, value]) => {
                if(value !== null && value !== undefined) {
                  formData.append(key, String(value));
                }
            });
            const csrfToken = getCookie(CSRF_FORM_NAME);
            if(csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);

            return upsertChannelFee(formData);
        },
        onSuccess: (result) => {
            if (result.success) {
                toast({ title: "Channel fee saved" });
                void queryClient.invalidateQueries({ queryKey: ['channelFees'] });
            } else {
                toast({ variant: 'destructive', title: "Save failed", description: result.error });
            }
        },
        onError: (error) => {
             toast({ variant: 'destructive', title: "Error", description: getErrorMessage(error) });
        }
    });

    const onSubmit = (data: z.infer<typeof FormSchema>) => {
        data.fees.forEach(fee => mutate(fee));
    };

    if (isLoading) {
        return <Card><CardHeader><CardTitle>Loading Channel Fees...</CardTitle></CardHeader><CardContent><Loader2 className="animate-spin" /></CardContent></Card>;
    }
    
    return (
        <Card>
            <CardHeader>
                <CardTitle>Channel Fee Management</CardTitle>
                <CardDescription>
                    Set fixed or percentage-based fees for your sales channels (e.g., Shopify, Amazon) to improve profit calculations.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                    <div className="space-y-4">
                        {fields.map((field, index) => (
                            <div key={field.id} className="grid grid-cols-1 md:grid-cols-[1fr_100px_100px_auto] gap-2 items-end">
                                <div>
                                    <Label>Channel Name</Label>
                                    <Input {...register(`fees.${index}.channel_name`)} placeholder="e.g., Shopify" />
                                </div>
                                <div>
                                    <Label>Fixed Fee ($)</Label>
                                    <Input type="number" step="0.01" {...register(`fees.${index}.fixed_fee`)} placeholder="e.g., 0.30" />
                                </div>
                                <div>
                                     <Label>Percentage (%)</Label>
                                    <Input type="number" step="0.1" {...register(`fees.${index}.percentage_fee`)} placeholder="e.g., 2.9" />
                                </div>
                                <Button type="button" variant="ghost" size="icon" onClick={() => remove(index)}>
                                    <Trash2 className="h-4 w-4" />
                                </Button>
                            </div>
                        ))}
                    </div>
                     {Object.keys(errors).length > 0 && <p className="text-sm text-destructive">Please check the errors above.</p>}
                    <div className="flex gap-2">
                        <Button type="button" variant="outline" onClick={() => append({ channel_name: '', fixed_fee: null, percentage_fee: null })}>
                            Add Channel
                        </Button>
                        <Button type="submit" disabled={isPending}>
                            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                            Save All Fees
                        </Button>
                    </div>
                </form>
            </CardContent>
        </Card>
    )
}
