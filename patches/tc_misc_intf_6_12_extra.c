struct tc_node_cache {
	bool value;
	bool checked;
};

static bool tc_node_available(struct device_node *np)
{
	if (!np)
		return false;
	return of_device_is_available(np);
}

static bool tc_check_node(struct device_node **cached_np,
			  struct tc_node_cache *cache,
			  const char *compatible)
{
	if (cache->checked)
		return cache->value;

	if (!*cached_np)
		*cached_np = of_find_compatible_node(NULL, NULL, compatible);

	if (!*cached_np) {
		pr_err("[misc_intf] %s: failed to get dts node compatible\n",
		       __func__);
		cache->value = false;
	} else {
		cache->value = tc_node_available(*cached_np);
	}

	cache->checked = true;
	return cache->value;
}

bool tc_is_dts_node_available(struct device_node *np)
{
	if (!np) {
		pr_err("[misc_intf] %s: fea NULL\n", __func__);
		return false;
	}
	return of_device_is_available(np);
}
EXPORT_SYMBOL(tc_is_dts_node_available);

bool tc_is_si_battery(void)
{
	static struct device_node *np;
	static struct tc_node_cache cache;
	struct misc_info *info = tc_get_misc_info();

	if (!info) {
		pr_err("[misc_intf] %s: %s: Failed to get misc info (info is NULL)\n",
		       __func__, "tc_is_si_battery");
		return false;
	}

	if (cache.checked)
		return cache.value;

	if (!np)
		np = of_find_compatible_node(NULL, NULL, "transsion, adapter_control");

	if (!np) {
		pr_err("[misc_intf] %s: get tc_misc info fail\n", __func__);
		return false;
	}

	/* Field `support_si_bat` dibaca dari DT oleh tc_misc_parse_dt(). */
	cache.value = info->support_si_bat;
	cache.checked = true;
	return cache.value;
}
EXPORT_SYMBOL(tc_is_si_battery);

bool tc_is_support_charge_transfer(void)
{
	static struct device_node *np;
	static struct tc_node_cache cache;

	if (!tc_get_misc_info()) {
		pr_err("[misc_intf] %s: %s: Failed to get misc info (info is NULL)\n",
		       __func__, "tc_is_support_charge_transfer");
		return false;
	}
	return tc_check_node(&np, &cache, "transsion, charge_transfer");
}
EXPORT_SYMBOL(tc_is_support_charge_transfer);

bool tc_is_support_battery_manager(void)
{
	static struct device_node *np;
	static struct tc_node_cache cache;

	if (!tc_get_misc_info()) {
		pr_err("[misc_intf] %s: %s: Failed to get misc info (info is NULL)\n",
		       __func__, "tc_is_support_battery_manager");
		return false;
	}
	return tc_check_node(&np, &cache, "tran,battery_manager");
}
EXPORT_SYMBOL(tc_is_support_battery_manager);

bool tc_is_support_temp_forecast(void)
{
	static struct device_node *np;
	static struct tc_node_cache cache;

	if (!tc_get_misc_info()) {
		pr_err("[misc_intf] %s: %s: Failed to get misc info (info is NULL)\n",
		       __func__, "tc_is_support_temp_forecast");
		return false;
	}
	return tc_check_node(&np, &cache, "tc,temp_forecast");
}
EXPORT_SYMBOL(tc_is_support_temp_forecast);

bool tc_is_support_adapter_control(void)
{
	static struct device_node *np;
	static struct tc_node_cache cache;

	if (!tc_get_misc_info()) {
		pr_err("[misc_intf] %s: %s: Failed to get misc info (info is NULL)\n",
		       __func__, "tc_is_support_adapter_control");
		return false;
	}
	return tc_check_node(&np, &cache, "transsion, adapter_control");
}
EXPORT_SYMBOL(tc_is_support_adapter_control);

bool tc_is_support_otg_ctrl(void)
{
	static struct device_node *np;
	static struct tc_node_cache cache;

	if (!tc_get_misc_info()) {
		pr_err("[misc_intf] %s: %s: Failed to get misc info (info is NULL)\n",
		       __func__, "tc_is_support_otg_ctrl");
		return false;
	}
	return tc_check_node(&np, &cache, "tran,otg_fun");
}
EXPORT_SYMBOL(tc_is_support_otg_ctrl);

int tc_get_battery_id(void)
{
	struct misc_info *info = tc_get_misc_info();
	union com_propval val;
	int ret;

	memset(&val, 0, sizeof(val));

	if (!info) {
		pr_err("[misc_intf] %s: Failed to get misc info (info is NULL)\n",
		       __func__);
		return -ENODEV;
	}

	if (!info->gauge_dev) {
		info->gauge_dev = tran_get_by_name("tc_gauge");
		if (IS_ERR_OR_NULL(info->gauge_dev)) {
			pr_err("[misc_intf] %s: %s Couldn't get dev(%s)\n",
			       __func__, "tc_get_battery_id", "tc_gauge");
			info->gauge_dev = NULL;
			return -ENODEV;
		}
	}

	ret = tran_dev_get_prop(info->gauge_dev, TRAN_PROP_BATTERY_ID, &val);
	if (ret < 0) {
		pr_err("[misc_intf] %s: %s: Failed to get misc info (info is NULL)\n",
		       __func__, "tc_get_battery_id");
		return ret;
	}

	pr_info("[misc_intf] %s: %s: Battery ID = %d\n",
		__func__, "tc_get_battery_id", val.intval);
	return val.intval;
}
EXPORT_SYMBOL(tc_get_battery_id);
