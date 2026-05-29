import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Chip,
  Divider,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  useDisclosure,
} from "@heroui/react";
import React, {
  forwardRef,
  useImperativeHandle,
  useState,
  useEffect,
} from "react";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { faExternalLink } from "@fortawesome/free-solid-svg-icons";
import { Icon } from "@iconify/react";
import { addToast } from "@heroui/toast";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { useTranslation } from "react-i18next";

import { buildApiUrl } from "@/lib/utils";

// 定义表单验证 schema
const securitySettingsSchema = z.object({
  // 保留空的 schema 以支持未来的设置项
});

type SecuritySettingsForm = z.infer<typeof securitySettingsSchema>;

// OAuth2 配置类型
interface OAuth2Config {
  clientId: string;
  clientSecret: string;
  authUrl: string;
  tokenUrl: string;
  userInfoUrl: string;
  userIdPath: string;
  scopes?: string[];
  /**
   * 回调地址，由前端根据 window.location.origin 生成并与其它配置一同保存
   */
  redirectUri?: string;
}

// 定义组件 ref 类型
export type SecuritySettingsRef = {
  submitForm: () => Promise<void>;
  resetForm: () => void;
};

const SecuritySettings = forwardRef<SecuritySettingsRef, {}>((props, ref) => {
  const { t } = useTranslation("settings");

  // 修改密码相关状态
  const {
    isOpen: isPasswordOpen,
    onOpen: onPasswordOpen,
    onOpenChange: onPasswordOpenChange,
  } = useDisclosure();
  const [passwordForm, setPasswordForm] = useState({
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
  });

  // 修改用户名相关状态
  const {
    isOpen: isUsernameOpen,
    onOpen: onUsernameOpen,
    onOpenChange: onUsernameOpenChange,
  } = useDisclosure();
  const [newUsername, setNewUsername] = useState("");

  // 全局提交状态（用户名/密码/OAuth2 配置共用）
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Cloudflare OAuth2 配置相关状态
  const {
    isOpen: isCloudflareOpen,
    onOpen: onCloudflareOpen,
    onOpenChange: onCloudflareOpenChange,
  } = useDisclosure();

  const [cloudflareConfig, setCloudflareConfig] = useState<OAuth2Config>({
    clientId: "",
    clientSecret: "",
    authUrl: "",
    tokenUrl: "",
    userInfoUrl: "",
    userIdPath: "sub",
    scopes: ["openid", "profile"],
  });

  // 模拟的配置状态（实际应该从后端获取）
  const [isCloudflareConfigured, setIsCloudflareConfigured] = useState(false);

  // 初始化表单
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<SecuritySettingsForm>({
    resolver: zodResolver(securitySettingsSchema),
    defaultValues: {},
  });

  // 初始化读取系统已绑定的 OAuth2 提供者及其配置
  useEffect(() => {
    const initOAuth2 = async () => {
      try {
        // 1) 获取当前绑定的 provider
        const res = await fetch(buildApiUrl("/api/oauth2/config"));
        const data = await res.json();

        if (!data.success) return;

        const curProvider = data.provider as "cloudflare" | "";

        if (!curProvider) return; // 未绑定

        const cfgData = data;

        if (curProvider === "cloudflare") {
          setCloudflareConfig((prev: any) => ({ ...prev, ...cfgData.config }));
          setIsCloudflareConfigured(true);
        }
      } catch (e) {
        console.error("初始化 OAuth2 配置失败", e);
      }
    };

    initOAuth2();
  }, []);

  // 修改密码功能（从 navbar-user.tsx 复制）
  const handlePasswordChange = async () => {
    // 验证表单
    if (
      !passwordForm.currentPassword ||
      !passwordForm.newPassword ||
      !passwordForm.confirmPassword
    ) {
      addToast({
        title: t("security.toast.validationFailed"),
        description: t("security.toast.fillAllFields"),
        color: "danger",
      });

      return;
    }

    if (passwordForm.newPassword !== passwordForm.confirmPassword) {
      addToast({
        title: t("security.toast.passwordMismatch"),
        description: t("security.toast.passwordMismatchDesc"),
        color: "danger",
      });

      return;
    }

    if (passwordForm.newPassword.length < 6) {
      addToast({
        title: t("security.toast.passwordTooShort"),
        description: t("security.toast.passwordTooShortDesc"),
        color: "danger",
      });

      return;
    }

    try {
      setIsSubmitting(true);

      const response = await fetch(buildApiUrl("/api/auth/change-password"), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          currentPassword: passwordForm.currentPassword,
          newPassword: passwordForm.newPassword,
        }),
      });

      const result = await response.json();

      if (response.ok && result.success) {
        addToast({
          title: t("security.toast.passwordChangeSuccess"),
          description: t("security.toast.passwordChangeSuccessDesc"),
          color: "success",
        });

        // 重置表单并关闭模态框
        setPasswordForm({
          currentPassword: "",
          newPassword: "",
          confirmPassword: "",
        });
        onPasswordOpenChange();
      } else {
        addToast({
          title: t("security.toast.passwordChangeFailed"),
          description: result.message || t("security.toast.checkCurrentPassword"),
          color: "danger",
        });
      }
    } catch (error) {
      console.error("修改密码失败:", error);
      addToast({
        title: t("security.toast.networkError"),
        description: t("security.toast.checkConnection"),
        color: "danger",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handlePasswordFormChange = (field: string, value: string) => {
    setPasswordForm((prev) => ({
      ...prev,
      [field]: value,
    }));
  };

  // 修改用户名功能
  const handleUsernameChange = async () => {
    if (!newUsername) {
      addToast({
        title: t("security.toast.validationFailed"),
        description: t("security.toast.fillUsername"),
        color: "danger",
      });

      return;
    }

    try {
      setIsSubmitting(true);

      const response = await fetch(buildApiUrl("/api/auth/change-username"), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ newUsername }),
      });

      const result = await response.json();

      if (response.ok && result.success) {
        addToast({
          title: t("security.toast.usernameChangeSuccess"),
          description: t("security.toast.usernameChangeSuccessDesc"),
          color: "success",
        });

        setNewUsername("");
        onUsernameOpenChange();

        // 刷新页面以便于获取最新用户信息
        window.location.reload();
      } else {
        addToast({
          title: t("security.toast.usernameChangeFailed"),
          description: result.message || t("security.toast.usernameChangeError"),
          color: "danger",
        });
      }
    } catch (error) {
      console.error("修改用户名失败:", error);
      addToast({
        title: t("security.toast.networkError"),
        description: t("security.toast.checkConnection"),
        color: "danger",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  // Cloudflare OAuth2 配置保存
  const handleSaveCloudflareConfig = async () => {
    try {
      setIsSubmitting(true);

      const redirectUri = `${window.location.origin}/api/oauth2/callback`;
      const payload = {
        provider: "cloudflare",
        config: {
          ...cloudflareConfig,
          redirectUri,
        },
      };

      const res = await fetch(buildApiUrl("/api/oauth2/config"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!res.ok) throw new Error("保存失败");

      addToast({
        title: t("security.toast.configSaveSuccess"),
        description: t("security.toast.cloudflareConfigSaved"),
        color: "success",
      });

      setIsCloudflareConfigured(true);
      onCloudflareOpenChange();
    } catch (error) {
      console.error("保存 Cloudflare 配置失败:", error);
      addToast({
        title: t("security.toast.configSaveFailed"),
        description: t("security.toast.cloudflareConfigError"),
        color: "danger",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  // 解绑处理
  const handleUnbindProvider = async (provider: "cloudflare") => {
    try {
      setIsSubmitting(true);
      const res = await fetch(buildApiUrl("/api/oauth2/config"), {
        method: "DELETE",
      });

      if (!res.ok) throw new Error("解绑失败");
      addToast({
        title: t("security.toast.unbindSuccess"),
        description: t("security.toast.unbindSuccessDesc"),
        color: "success",
      });
      setIsCloudflareConfigured(false);
    } catch (e) {
      console.error("解绑失败", e);
      addToast({
        title: t("security.toast.unbindFailed"),
        description: t("security.toast.unbindError"),
        color: "danger",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  // 处理表单提交
  const onSubmit = async (data: SecuritySettingsForm) => {
    try {
      // TODO: 调用后端 API 保存设置
      console.log("保存设置:", data);
    } catch (error) {
      console.error("保存设置失败:", error);
      throw error;
    }
  };

  // 暴露方法给父组件
  useImperativeHandle(ref, () => ({
    submitForm: () => handleSubmit(onSubmit)(),
    resetForm: () => reset(),
  }));

  return (
    <>
      <form>
        {/* 基础安全设置卡片 */}
        <Card className="mt-5 p-2">
          <CardHeader className="flex gap-3">
            <div className="flex flex-col flex-1">
              <p className="text-lg font-semibold">{t("security.basic.title")}</p>
              <p className="text-sm text-default-500">{t("security.basic.description")}</p>
            </div>
          </CardHeader>
          <Divider />
          <CardBody className="p-0">
            <div className="divide-y divide-default-200">
              <div className="flex items-center justify-between px-4 py-3">
                <div className="space-y-1">
                  <h3 className="text-base font-medium">{t("security.username.title")}</h3>
                  <p className="text-sm text-default-500">{t("security.username.description")}</p>
                </div>
                <Button
                  color="primary"
                  size="sm"
                  startContent={<Icon icon="solar:user-bold" width={18} />}
                  onPress={onUsernameOpen}
                >
                  {t("security.username.button")}
                </Button>
              </div>

              <div className="flex items-center justify-between px-4 py-3">
                <div className="space-y-1">
                  <h3 className="text-base font-medium">{t("security.password.title")}</h3>
                  <p className="text-sm text-default-500">
                    {t("security.password.description")}
                  </p>
                </div>
                <Button
                  color="primary"
                  size="sm"
                  startContent={<Icon icon="solar:key-bold" width={18} />}
                  onPress={onPasswordOpen}
                >
                  {t("security.password.button")}
                </Button>
              </div>
            </div>
          </CardBody>
        </Card>
      </form>

      {/* 修改密码模态框 */}
      <Modal
        backdrop="blur"
        classNames={{
          backdrop:
            "bg-gradient-to-t from-zinc-900 to-zinc-900/10 backdrop-opacity-20",
        }}
        isOpen={isPasswordOpen}
        placement="center"
        onOpenChange={onPasswordOpenChange}
      >
        <ModalContent>
          {(onClose) => (
            <>
              <ModalHeader className="flex flex-col gap-1">
                <div className="flex items-center gap-2">
                  <Icon
                    className="text-primary"
                    icon="solar:key-bold"
                    width={24}
                  />
                  {t("security.password.modalTitle")}
                </div>
              </ModalHeader>
              <ModalBody>
                <div className="flex flex-col gap-4">
                  <Input
                    label={t("security.password.currentPassword")}
                    placeholder={t("security.password.currentPasswordPlaceholder")}
                    startContent={
                      <Icon icon="solar:lock-password-bold" width={18} />
                    }
                    type="password"
                    value={passwordForm.currentPassword}
                    variant="bordered"
                    onChange={(e) =>
                      handlePasswordFormChange(
                        "currentPassword",
                        e.target.value,
                      )
                    }
                  />

                  <Input
                    label={t("security.password.newPassword")}
                    placeholder={t("security.password.newPasswordPlaceholder")}
                    startContent={<Icon icon="solar:key-bold" width={18} />}
                    type="password"
                    value={passwordForm.newPassword}
                    variant="bordered"
                    onChange={(e) =>
                      handlePasswordFormChange("newPassword", e.target.value)
                    }
                  />

                  <Input
                    label={t("security.password.confirmPassword")}
                    placeholder={t("security.password.confirmPasswordPlaceholder")}
                    startContent={<Icon icon="solar:key-bold" width={18} />}
                    type="password"
                    value={passwordForm.confirmPassword}
                    variant="bordered"
                    onChange={(e) =>
                      handlePasswordFormChange(
                        "confirmPassword",
                        e.target.value,
                      )
                    }
                  />

                  <div className="text-small text-default-500">
                    <p>• {t("security.password.requirements.minLength")}</p>
                    <p>• {t("security.password.requirements.recommended")}</p>
                  </div>
                </div>
              </ModalBody>
              <ModalFooter>
                <Button
                  color="danger"
                  isDisabled={isSubmitting}
                  variant="light"
                  onPress={onClose}
                >
                  {t("security.password.cancel")}
                </Button>
                <Button
                  color="primary"
                  isLoading={isSubmitting}
                  startContent={
                    !isSubmitting ? (
                      <Icon icon="solar:check-circle-bold" width={18} />
                    ) : null
                  }
                  onPress={handlePasswordChange}
                >
                  {isSubmitting ? t("security.password.submitting") : t("security.password.confirm")}
                </Button>
              </ModalFooter>
            </>
          )}
        </ModalContent>
      </Modal>

      {/* 修改用户名模态框 */}
      <Modal
        backdrop="blur"
        classNames={{
          backdrop:
            "bg-gradient-to-t from-zinc-900 to-zinc-900/10 backdrop-opacity-20",
        }}
        isOpen={isUsernameOpen}
        placement="center"
        onOpenChange={onUsernameOpenChange}
      >
        <ModalContent>
          {(onClose) => (
            <>
              <ModalHeader className="flex flex-col gap-1">
                <div className="flex items-center gap-2">
                  <Icon
                    className="text-primary"
                    icon="solar:user-bold"
                    width={24}
                  />
                  {t("security.username.modalTitle")}
                </div>
              </ModalHeader>
              <ModalBody>
                <Input
                  label={t("security.username.label")}
                  placeholder={t("security.username.placeholder")}
                  startContent={<Icon icon="solar:user-bold" width={18} />}
                  value={newUsername}
                  variant="bordered"
                  onChange={(e) => setNewUsername(e.target.value)}
                />
              </ModalBody>
              <ModalFooter>
                <Button
                  color="danger"
                  isDisabled={isSubmitting}
                  variant="light"
                  onPress={onClose}
                >
                  {t("security.username.cancel")}
                </Button>
                <Button
                  color="primary"
                  isLoading={isSubmitting}
                  startContent={
                    !isSubmitting ? (
                      <Icon icon="solar:check-circle-bold" width={18} />
                    ) : null
                  }
                  onPress={handleUsernameChange}
                >
                  {isSubmitting ? t("security.username.submitting") : t("security.username.confirm")}
                </Button>
              </ModalFooter>
            </>
          )}
        </ModalContent>
      </Modal>

      {/* OAuth2 设置卡片 */}
      <Card className="mt-8 p-2">
        <CardHeader className="flex gap-3">
          <div className="flex flex-col flex-1">
            <p className="text-lg font-semibold">{t("security.oauth2.title")}</p>
            <p className="text-sm text-default-500">
              {t("security.oauth2.description")}
            </p>
          </div>
        </CardHeader>
        <Divider />
        <CardBody className="p-4">
          {isCloudflareConfigured ? (
            // 已绑定状态
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Icon
                  height={24}
                  icon="simple-icons:cloudflare"
                  width={24}
                />
                <span className="font-medium">Cloudflare</span>
                <Chip color="success" size="sm" variant="flat">
                  {t("security.oauth2.bound")}
                </Chip>
              </div>
              <div className="flex gap-2">
                <Button
                  color="primary"
                  size="sm"
                  startContent={<Icon icon="solar:settings-bold" width={18} />}
                  onPress={() => onCloudflareOpen()}
                >
                  {t("security.oauth2.configure")}
                </Button>
                <Button
                  color="danger"
                  isLoading={isSubmitting}
                  size="sm"
                  startContent={
                    <Icon icon="solar:lock-keyhole-unlocked-bold" width={18} />
                  }
                  onPress={() => handleUnbindProvider("cloudflare")}
                >
                  {t("security.oauth2.unbind")}
                </Button>
              </div>
            </div>
          ) : (
            // 未绑定状态
            <div className="flex items-center justify-between">
              <p className="text-default-500">{t("security.oauth2.notBound")}</p>
              <Button
                className="text-white"
                color="primary"
                size="sm"
                startContent={<Icon icon="solar:add-circle-bold" width={18} />}
                onPress={onCloudflareOpen}
              >
                {t("security.oauth2.bindButton")}
              </Button>
            </div>
          )}
        </CardBody>
      </Card>

      {/* Cloudflare OAuth2 配置模态框 */}
      <Modal
        backdrop="blur"
        isOpen={isCloudflareOpen}
        placement="center"
        size="2xl"
        onOpenChange={onCloudflareOpenChange}
      >
        <ModalContent>
          {(onClose) => (
            <>
              <ModalHeader className="flex items-center  w-full">
                <span>{t("security.oauth2.cloudflare.title")}</span>
                <FontAwesomeIcon
                  className="text-[12px] text-default-400 hover:text-default-500 cursor-pointer ml-2 inline align-baseline"
                  icon={faExternalLink}
                  onClick={(e) => {
                    window.open("https://one.dash.cloudflare.com/", "_blank");
                  }}
                />
              </ModalHeader>
              <ModalBody>
                <div className="space-y-4">
                  <Input
                    label={t("security.oauth2.cloudflare.clientId")}
                    placeholder={t("security.oauth2.cloudflare.clientIdPlaceholder")}
                    value={cloudflareConfig.clientId}
                    onChange={(e) =>
                      setCloudflareConfig((prev) => ({
                        ...prev,
                        clientId: e.target.value,
                      }))
                    }
                  />
                  <Input
                    label={t("security.oauth2.cloudflare.clientSecret")}
                    placeholder={t("security.oauth2.cloudflare.clientSecretPlaceholder")}
                    type="password"
                    value={cloudflareConfig.clientSecret}
                    onChange={(e) =>
                      setCloudflareConfig((prev) => ({
                        ...prev,
                        clientSecret: e.target.value,
                      }))
                    }
                  />
                  <Input
                    label={t("security.oauth2.cloudflare.authUrl")}
                    placeholder={t("security.oauth2.cloudflare.authUrlPlaceholder")}
                    value={cloudflareConfig.authUrl}
                    onChange={(e) =>
                      setCloudflareConfig((prev) => ({
                        ...prev,
                        authUrl: e.target.value,
                      }))
                    }
                  />
                  <Input
                    label={t("security.oauth2.cloudflare.tokenUrl")}
                    placeholder={t("security.oauth2.cloudflare.tokenUrlPlaceholder")}
                    value={cloudflareConfig.tokenUrl}
                    onChange={(e) =>
                      setCloudflareConfig((prev) => ({
                        ...prev,
                        tokenUrl: e.target.value,
                      }))
                    }
                  />
                  <Input
                    label={t("security.oauth2.cloudflare.userInfoUrl")}
                    placeholder={t("security.oauth2.cloudflare.userInfoUrlPlaceholder")}
                    value={cloudflareConfig.userInfoUrl}
                    onChange={(e) =>
                      setCloudflareConfig((prev) => ({
                        ...prev,
                        userInfoUrl: e.target.value,
                      }))
                    }
                  />
                </div>
              </ModalBody>
              <ModalFooter>
                <Button color="default" variant="light" onPress={onClose}>
                  {t("security.oauth2.cloudflare.cancel")}
                </Button>
                <Button
                  color="primary"
                  isLoading={isSubmitting}
                  onPress={handleSaveCloudflareConfig}
                >
                  {t("security.oauth2.cloudflare.save")}
                </Button>
              </ModalFooter>
            </>
          )}
        </ModalContent>
      </Modal>
    </>
  );
});

SecuritySettings.displayName = "SecuritySettings";

export default SecuritySettings;
