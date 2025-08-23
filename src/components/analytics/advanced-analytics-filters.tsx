'use client';

import React, { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { DatePickerWithRange } from '@/components/ui/date-range-picker';
import { Checkbox } from '@/components/ui/checkbox';
import { Badge } from '@/components/ui/badge';
import { X, Filter, Download, Calendar, Tags, TrendingUp } from 'lucide-react';
import { DateRange } from 'react-day-picker';

interface AnalyticsFilter {
  dateRange?: DateRange;
  categories: string[];
  suppliers: string[];
  channels: string[];
  minRevenue?: number;
  maxRevenue?: number;
  sortBy: 'revenue' | 'date' | 'quantity' | 'margin';
  sortDirection: 'asc' | 'desc';
  groupBy: 'product' | 'category' | 'supplier' | 'channel' | 'date';
}

interface AdvancedAnalyticsFiltersProps {
  onFilterChange: (filters: AnalyticsFilter) => void;
  onExport: (format: 'csv' | 'excel' | 'pdf') => void;
  availableCategories: string[];
  availableSuppliers: string[];
}

export default function AdvancedAnalyticsFilters({
  onFilterChange,
  onExport,
  availableCategories,
  availableSuppliers
}: AdvancedAnalyticsFiltersProps) {
  const [filters, setFilters] = useState<AnalyticsFilter>({
    categories: [],
    suppliers: [],
    channels: [],
    sortBy: 'revenue',
    sortDirection: 'desc',
    groupBy: 'product'
  });

  const [isExpanded, setIsExpanded] = useState(false);

  const updateFilter = (key: keyof AnalyticsFilter, value: any) => {
    const newFilters = { ...filters, [key]: value };
    setFilters(newFilters);
    onFilterChange(newFilters);
  };

  const toggleArrayFilter = (key: 'categories' | 'suppliers' | 'channels', value: string) => {
    const currentArray = filters[key];
    const newArray = currentArray.includes(value)
      ? currentArray.filter(item => item !== value)
      : [...currentArray, value];
    
    updateFilter(key, newArray);
  };

  const clearFilters = () => {
    const clearedFilters: AnalyticsFilter = {
      categories: [],
      suppliers: [],
      channels: [],
      sortBy: 'revenue',
      sortDirection: 'desc',
      groupBy: 'product'
    };
    setFilters(clearedFilters);
    onFilterChange(clearedFilters);
  };

  const getActiveFilterCount = () => {
    let count = 0;
    if (filters.dateRange) count++;
    if (filters.categories.length > 0) count++;
    if (filters.suppliers.length > 0) count++;
    if (filters.channels.length > 0) count++;
    if (filters.minRevenue || filters.maxRevenue) count++;
    return count;
  };

  return (
    <Card className="mb-6">
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-2">
            <Filter className="h-5 w-5" />
            <CardTitle>Advanced Filters & Export</CardTitle>
            {getActiveFilterCount() > 0 && (
              <Badge variant="secondary">
                {getActiveFilterCount()} active
              </Badge>
            )}
          </div>
          <div className="flex items-center space-x-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setIsExpanded(!isExpanded)}
            >
              {isExpanded ? 'Collapse' : 'Expand'} Filters
            </Button>
            {getActiveFilterCount() > 0 && (
              <Button variant="outline" size="sm" onClick={clearFilters}>
                <X className="h-4 w-4 mr-1" />
                Clear All
              </Button>
            )}
          </div>
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Quick Filters */}
        <div className="flex flex-wrap gap-2">
          <Button
            variant={filters.dateRange ? 'default' : 'outline'}
            size="sm"
            onClick={() => updateFilter('dateRange', { 
              from: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), 
              to: new Date() 
            })}
          >
            <Calendar className="h-4 w-4 mr-1" />
            Last 7 Days
          </Button>
          <Button
            variant={filters.dateRange ? 'default' : 'outline'}
            size="sm"
            onClick={() => updateFilter('dateRange', { 
              from: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000), 
              to: new Date() 
            })}
          >
            <Calendar className="h-4 w-4 mr-1" />
            Last 30 Days
          </Button>
          <Button
            variant={filters.sortBy === 'revenue' ? 'default' : 'outline'}
            size="sm"
            onClick={() => updateFilter('sortBy', 'revenue')}
          >
            <TrendingUp className="h-4 w-4 mr-1" />
            By Revenue
          </Button>
        </div>

        {/* Expanded Filters */}
        {isExpanded && (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 pt-4 border-t">
            {/* Date Range */}
            <div className="space-y-2">
              <Label>Date Range</Label>
              <DatePickerWithRange
                date={filters.dateRange}
                onDateChange={(dateRange: DateRange | undefined) => updateFilter('dateRange', dateRange)}
              />
            </div>

            {/* Categories */}
            <div className="space-y-2">
              <Label>Categories</Label>
              <div className="space-y-2 max-h-32 overflow-y-auto">
                {availableCategories.map((category) => (
                  <div key={category} className="flex items-center space-x-2">
                    <Checkbox
                      id={`category-${category}`}
                      checked={filters.categories.includes(category)}
                      onCheckedChange={() => toggleArrayFilter('categories', category)}
                    />
                    <Label htmlFor={`category-${category}`} className="text-sm">
                      {category}
                    </Label>
                  </div>
                ))}
              </div>
            </div>

            {/* Suppliers */}
            <div className="space-y-2">
              <Label>Suppliers</Label>
              <div className="space-y-2 max-h-32 overflow-y-auto">
                {availableSuppliers.map((supplier) => (
                  <div key={supplier} className="flex items-center space-x-2">
                    <Checkbox
                      id={`supplier-${supplier}`}
                      checked={filters.suppliers.includes(supplier)}
                      onCheckedChange={() => toggleArrayFilter('suppliers', supplier)}
                    />
                    <Label htmlFor={`supplier-${supplier}`} className="text-sm">
                      {supplier}
                    </Label>
                  </div>
                ))}
              </div>
            </div>

            {/* Revenue Range */}
            <div className="space-y-2">
              <Label>Revenue Range</Label>
              <div className="flex space-x-2">
                <Input
                  type="number"
                  placeholder="Min"
                  value={filters.minRevenue || ''}
                  onChange={(e) => updateFilter('minRevenue', e.target.value ? Number(e.target.value) : undefined)}
                />
                <Input
                  type="number"
                  placeholder="Max"
                  value={filters.maxRevenue || ''}
                  onChange={(e) => updateFilter('maxRevenue', e.target.value ? Number(e.target.value) : undefined)}
                />
              </div>
            </div>

            {/* Sort By */}
            <div className="space-y-2">
              <Label>Sort By</Label>
              <Select value={filters.sortBy} onValueChange={(value) => updateFilter('sortBy', value)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="revenue">Revenue</SelectItem>
                  <SelectItem value="date">Date</SelectItem>
                  <SelectItem value="quantity">Quantity</SelectItem>
                  <SelectItem value="margin">Margin</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Group By */}
            <div className="space-y-2">
              <Label>Group By</Label>
              <Select value={filters.groupBy} onValueChange={(value) => updateFilter('groupBy', value)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="product">Product</SelectItem>
                  <SelectItem value="category">Category</SelectItem>
                  <SelectItem value="supplier">Supplier</SelectItem>
                  <SelectItem value="channel">Channel</SelectItem>
                  <SelectItem value="date">Date</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        )}

        {/* Export Options */}
        <div className="flex items-center justify-between pt-4 border-t">
          <div className="flex items-center space-x-2">
            <Download className="h-4 w-4" />
            <span className="text-sm font-medium">Export Data:</span>
          </div>
          <div className="flex space-x-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => onExport('csv')}
            >
              CSV
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => onExport('excel')}
            >
              Excel
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => onExport('pdf')}
            >
              PDF
            </Button>
          </div>
        </div>

        {/* Active Filters Display */}
        {getActiveFilterCount() > 0 && (
          <div className="flex flex-wrap gap-2 pt-4 border-t">
            {filters.dateRange && (
              <Badge variant="secondary" className="flex items-center gap-1">
                <Calendar className="h-3 w-3" />
                Date Range
                <X 
                  className="h-3 w-3 cursor-pointer" 
                  onClick={() => updateFilter('dateRange', undefined)}
                />
              </Badge>
            )}
            {filters.categories.map((category) => (
              <Badge key={category} variant="secondary" className="flex items-center gap-1">
                <Tags className="h-3 w-3" />
                {category}
                <X 
                  className="h-3 w-3 cursor-pointer" 
                  onClick={() => toggleArrayFilter('categories', category)}
                />
              </Badge>
            ))}
            {filters.suppliers.map((supplier) => (
              <Badge key={supplier} variant="secondary" className="flex items-center gap-1">
                {supplier}
                <X 
                  className="h-3 w-3 cursor-pointer" 
                  onClick={() => toggleArrayFilter('suppliers', supplier)}
                />
              </Badge>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
