$(function () {
    //uid = 'abcd1';	
	if(pageType == 'index'){
		if (uid != null && uid.length > 0 && uid != 'null') {
			// cas途径登录成功
			loginInUserRegister(uid).done(function(resp){
				var code = resp.code;
				var data = resp.data;
				if (code != null && code == "1") {                        
					var number = data.number;// 学号
					var token = data.token;// 登录凭证
					// 保存登录凭证在本地缓存中
					sessionStorage.removeItem("token");
					sessionStorage.setItem("token", token); 
					// 初始化学生信息
					CVStudentLogin.studentInfo(number);
				}else if (code == '4') {
					var stu = $('#stundentinfoDiv');
					stu.css("display", "block");
					var template = $('#no_student_info').html();
					stu.html(template);
					$('#login_error_message').html('在线人数超过上限，请稍后再试！').css('font-size', '16px');
					stu.find('button').hide();
				} else {
					// 没有找到学生信息，跳转回登录页面
					var stu = $('#stundentinfoDiv');
					stu.css("display", "block");
					var template = $('#no_student_info').html();
					stu.html(template);
					$('#login_error_title').html('无学籍信息');
					$('#login_error_message').html('登录的账户未查询到学籍信息，请点击“重新登录”按钮回到登录页面，使用学生账户登录系统。');
				}
			});
		} else {
			// 未获得头部登录信息
			if (loginType != null && loginType == 'cas') {
				// 登录方式是cas，跳转至登录地址
				window.location.href = casUrl;
			} else {
				// 登录方式是普通方式
				$("#loginDiv").css("display", "block");
			}
		}
	}else{
		if(!document.URL || (document.URL.indexOf('xsxkapp') > -1 
									&& document.URL.indexOf('/index.do') == -1 
									&& document.URL.indexOf('/grablessons.do') == -1 
									&& document.URL.indexOf('/curriculavariable.do') == -1 
									&& document.URL.indexOf('/expcurriculavariable.do') == -1)){
			window.location.href = BaseUrl + "/sys/xsxkapp/*default/index.do";
		}
	}
});
