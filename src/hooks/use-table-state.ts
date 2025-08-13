
'use client';

import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useDebouncedCallback } from 'use-debounce';

type UseTableStateProps<T extends string> = {
    searchParamName?: string;
    pageParamName?: string;
    limitParamName?: string;
    sortColumnParamName?: string;
    sortDirectionParamName?: string;
    defaultSortColumn: T;
    defaultSortDirection?: 'asc' | 'desc';
};

export function useTableState<T extends string>({
    searchParamName = 'query',
    pageParamName = 'page',
    sortColumnParamName = 'sortBy',
    sortDirectionParamName = 'sortDirection',
    defaultSortColumn,
    defaultSortDirection = 'asc',
}: UseTableStateProps<T>) {
    const router = useRouter();
    const pathname = usePathname();
    const searchParams = useSearchParams();

    const searchQuery = searchParams.get(searchParamName) || '';
    const page = Number(searchParams.get(pageParamName)) || 1;
    const sortBy = (searchParams.get(sortColumnParamName) as T | null) || defaultSortColumn;
    const sortDirection = searchParams.get(sortDirectionParamName) === 'desc' ? 'desc' : 'asc';
    
    const createURL = (newParams: Record<string, string | number>) => {
        const params = new URLSearchParams(searchParams.toString());
        for (const [key, value] of Object.entries(newParams)) {
            if (value) {
                params.set(key, String(value));
            } else {
                params.delete(key);
            }
            // Always reset to page 1 on search or sort change
            if (key !== pageParamName) {
                params.set(pageParamName, '1');
            }
        }
        return `${pathname}?${params.toString()}`;
    };

    const handleSearch = useDebouncedCallback((term: string) => {
        router.replace(createURL({ [searchParamName]: term }));
    }, 300);

    const handleSort = (column: T) => {
        const newDirection = sortBy === column && sortDirection === 'asc' ? 'desc' : 'asc';
        router.push(createURL({ [sortColumnParamName]: column, [sortDirectionParamName]: newDirection }));
    };

    const handlePageChange = (newPage: number) => {
        router.push(createURL({ [pageParamName]: newPage }));
    }

    return {
        searchQuery,
        page,
        sortBy,
        sortDirection,
        handleSearch,
        handleSort,
        handlePageChange
    };
}
