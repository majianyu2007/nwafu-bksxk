/**
 * 查询成绩信息
 */
function queryXkScore(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/xscj.do",
        queryParam,
        "post", 
        {}, 
        {"token": sessionStorage.token}
    );
}