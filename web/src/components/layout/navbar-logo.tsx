import { NavbarBrand, Link, cn, Chip } from "@heroui/react";

import { fontSans } from "@/config/fonts";
import { getVersion } from "@/lib/version";

/**
 * 导航栏Logo组件
 */
export const NavbarLogo = () => {
  // 检测环境和版本
  const isDev = import.meta.env.DEV;
  const version = getVersion();
  const isBeta = version.includes('beta');

  // 确定badge内容和颜色
  const getBadgeProps = () => {
    if (isDev) {
      return { content: "dev", color: "default" as const };
    }
    if (isBeta) {
      return { content: "beta", color: "primary" as const };
    }
    return null;
  };

  const badgeProps = getBadgeProps();

  return (
    <NavbarBrand as="li" className="gap-3 max-w-fit">
      <Link className="flex justify-start items-center" href="/">
        <img src="/favicon.ico" alt="NB面板" className="w-8 h-8" />
        <p className={cn("font-bold text-foreground pl-1", fontSans.className)}>
          NB面板
        </p>
        {badgeProps && (
          <Chip variant="flat" color={badgeProps.color} size="sm" className="h-5 p-0 ml-1">
            {badgeProps.content}
          </Chip>
        )}
      </Link>
    </NavbarBrand>
  );
};
