function queryStudentReturnResults(queryParam) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/returnResults.do?timestamp=" + timestamp,
        queryParam == null ? {} : queryParam,
        "get",
        {},
        {"token" : sessionStorage.token}
    );
}