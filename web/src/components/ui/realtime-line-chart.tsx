"use client";

import React, { useMemo } from "react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
} from "recharts";

export interface RealtimeDataPoint {
  timestamp: number;
  date: string;
  [key: string]: number | string | undefined;
}

export interface DataSeries {
  key: string;
  name: string;
  color: string;
  unit: string;
  yAxisId: "left" | "right";
}

export interface RealtimeLineChartProps {
  className?: string;
  data: RealtimeDataPoint[];
  height?: number;
  isDualAxis?: boolean;
  leftYAxisLabel?: string;
  maxDataPoints?: number;
  rightYAxisLabel?: string;
  series: DataSeries[];
}

export const RealtimeLineChart: React.FC<RealtimeLineChartProps> = ({
  className = "",
  data,
  height = 300,
  isDualAxis = false,
  leftYAxisLabel,
  rightYAxisLabel,
  series,
}) => {
  const formattedData = useMemo(() => {
    return data.map((point) => ({
      ...point,
      date: point.date || new Date(point.timestamp).toLocaleTimeString(),
    }));
  }, [data]);

  if (!data.length || !series.length) {
    return <div className={className} style={{ height }} />;
  }

  return (
    <div className={className} style={{ width: "100%", height }}>
      <ResponsiveContainer>
        <LineChart data={formattedData}>
          <CartesianGrid strokeDasharray="3 3" opacity={0.3} />
          <XAxis dataKey="date" fontSize={11} />
          <YAxis
            yAxisId="left"
            label={
              leftYAxisLabel
                ? { value: leftYAxisLabel, angle: -90, position: "insideLeft", fontSize: 11 }
                : undefined
            }
            fontSize={11}
          />
          {isDualAxis && rightYAxisLabel && (
            <YAxis
              yAxisId="right"
              orientation="right"
              label={{
                value: rightYAxisLabel,
                angle: 90,
                position: "insideRight",
                fontSize: 11,
              }}
              fontSize={11}
            />
          )}
          <Tooltip />
          <Legend />
          {series.map((s) => (
            <Line
              key={s.key}
              dataKey={s.key}
              name={s.name}
              stroke={s.color}
              yAxisId={s.yAxisId}
              dot={false}
              isAnimationActive={false}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
};
