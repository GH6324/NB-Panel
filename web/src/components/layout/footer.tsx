import { useTranslation } from "react-i18next";
import { getVersion } from "@/lib/version";

/**
 * 页脚组件
 */
export const Footer = () => {
  const { t } = useTranslation();

  return (
    <footer className="w-full flex items-center justify-center py-3">
      <div className="text-default-600 text-sm">
        {t("footer.copyright")} | {t("footer.version")}
        {getVersion()} | 希音互联
      </div>
    </footer>
  );
};
